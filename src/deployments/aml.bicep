param location string
@minLength(5)
param prefix string
param ip_list string
param user_object_id string
var subnets = [
  'default'
  'resources'
  'aml'
]
var vnet_name = '${prefix}-vnet'
resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: vnet_name
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      for (subnetName, i) in subnets: {
        name: subnetName
        properties: {
          addressPrefix: '10.0.${i}.0/24'
          privateEndpointNetworkPolicies: (subnetName == 'resources') ? 'NetworkSecurityGroupEnabled' : 'Disabled'
          delegations: (subnetName == 'aml')
            ? [
                {
                  name: 'Microsoft.MachineLearningServices/workspaceComputes'
                  properties: {
                    serviceName: 'Microsoft.MachineLearningServices/workspaceComputes'
                  }
                  type: 'Microsoft.Network/virtualNetworks/subnets/delegations'
                }
              ]
            : []
        }
      }
    ]
  }
}

// create log analytics workspace
resource log_analytics_workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${prefix}-law'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
  }
}

// create application insights that uses the log analytics workspace
resource app_insights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${prefix}-ai'
  location: location
  kind: 'web'
  properties: {
    RetentionInDays: 30
    IngestionMode: 'LogAnalytics'
    Application_Type: 'web'
    Flow_Type: 'Redfield'
    Request_Source: 'IbizaAIExtension'
    WorkspaceResourceId: log_analytics_workspace.id
  }
}

// create a managed identity
resource managed_identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-07-31-preview' = {
  name: '${prefix}-mi'
  location: location
}

// create a storage account
resource storage_account 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: '${prefix}sa'
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      ipRules: [
        for ip in split(ip_list, ','): {
          value: ip
          action: 'Allow'
        }
      ]
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
  }
}

// create storage blob service
resource storage_blob_service 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage_account
  name: 'default'
}

// create storage container
resource storage_container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: storage_blob_service
  name: 'default'
  properties: {
    publicAccess: 'None'
  }
}

resource storage_container_job_input 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: storage_blob_service
  name: 'jobinput'
  properties: {
    publicAccess: 'None'
  }
}

resource storage_container_job_output 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: storage_blob_service
  name: 'joboutput'
  properties: {
    publicAccess: 'None'
  }
}

var storage_resources = [
  'blob'
  'queue'
  'table'
]
resource storage_account_private_endpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = [
  for storage_resource in storage_resources: {
    name: '${prefix}-${storage_resource}-sa-pe'
    location: location
    properties: {
      subnet: {
        id: vnet.properties.subnets[1].id
      }
      privateLinkServiceConnections: [
        {
          name: 'storageaccount'
          properties: {
            privateLinkServiceId: storage_account.id
            groupIds: [
              storage_resource
            ]
          }
        }
      ]
    }
  }
]

resource storage_account_private_dns_zone 'Microsoft.Network/privateDnsZones@2020-06-01' = [
  for storage_resource in storage_resources: {
    name: 'privatelink.${storage_resource}.${environment().suffixes.storage}'
    location: 'global'
    dependsOn: [
      vnet
    ]
  }
]

resource storage_account_private_dns_zone_link 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [
  for (storage_resource, i) in storage_resources: {
    parent: storage_account_private_dns_zone[i]
    name: '${storage_account_private_dns_zone[i].name}-link'
    location: 'global'
    properties: {
      registrationEnabled: false
      virtualNetwork: {
        id: vnet.id
      }
    }
  }
]

resource storage_account_private_endpoint_dns_group 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = [
  for (storage_resource, i) in storage_resources: {
    parent: storage_account_private_endpoint[i]
    name: 'storageaccountdnsgroupname'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'config1'
          properties: {
            privateDnsZoneId: storage_account_private_dns_zone[i].id
          }
        }
      ]
    }
  }
]

// create azure key vault
resource key_vault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: '${prefix}-kv'
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      ipRules: [
        for ip in split(ip_list, ','): {
          value: ip
        }
      ]
    }
  }
}

resource keyvaultsecretsuser_role_assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().subscriptionId, managed_identity.name, 'KeyVaultSecretsUser')
  scope: key_vault
  properties: {
    principalId: managed_identity.properties.principalId
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '4633458b-17de-408a-b874-0445c86b69e6'
    )
  }
}

resource keyvaultsecretsuser_user_role_assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().subscriptionId, user_object_id, 'KeyVaultSecretsUser')
  scope: key_vault
  properties: {
    principalId: user_object_id
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '4633458b-17de-408a-b874-0445c86b69e6'
    )
  }
}

// create a private endpoint for the key vault
resource key_vault_private_endpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: '${prefix}-kv-pe'
  location: location
  properties: {
    subnet: {
      id: vnet.properties.subnets[1].id
    }
    privateLinkServiceConnections: [
      {
        name: 'keyvault'
        properties: {
          privateLinkServiceId: key_vault.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }
}

// create private dns for the key vault private endpoint
resource key_vault_private_dns_zone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
  dependsOn: [
    vnet
  ]
}

resource key_vault_private_dns_zone_link 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: key_vault_private_dns_zone
  name: '${key_vault_private_dns_zone.name}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource key_vault_private_endpoint_dns_group 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: key_vault_private_endpoint
  name: 'keyvaultdnsgroupname'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config1'
        properties: {
          privateDnsZoneId: key_vault_private_dns_zone.id
        }
      }
    ]
  }
}

// create azure container registry
resource container_registry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: '${prefix}acr'
  location: location
  sku: {
    name: 'Premium'
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled'
    networkRuleSet: {
      defaultAction: 'Deny'
      ipRules: [
        for ip in split(ip_list, ','): {
          value: ip
          action: 'Allow'
        }
      ]
    }
    zoneRedundancy: 'Disabled'
    networkRuleBypassOptions: 'AzureServices'
  }
}

resource container_registry_private_endpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: '${prefix}-acr-pe'
  location: location
  properties: {
    subnet: {
      id: vnet.properties.subnets[1].id
    }
    privateLinkServiceConnections: [
      {
        name: 'registry'
        properties: {
          privateLinkServiceId: container_registry.id
          groupIds: [
            'registry'
          ]
        }
      }
    ]
  }
}

resource container_registry_private_dns_zone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: 'privatelink.azurecr.io'
  location: 'global'
  dependsOn: [
    vnet
  ]
}

resource container_registry_private_dns_zone_link 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: container_registry_private_dns_zone
  name: '${container_registry_private_dns_zone.name}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

resource container_registry_private_endpoint_dns_group 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: container_registry_private_endpoint
  name: 'containerregistrydnsgroupname'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'config1'
        properties: {
          privateDnsZoneId: container_registry_private_dns_zone.id
        }
      }
    ]
  }
}

resource acrpull_role_assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().subscriptionId, managed_identity.name, 'AcrPull')
  scope: container_registry
  properties: {
    principalId: managed_identity.properties.principalId
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '7f951dda-4ed3-4680-a7ca-43fe172d538d'
    )
  }
}

resource acrpull_user_role_assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().subscriptionId, user_object_id, 'AcrPull')
  scope: container_registry
  properties: {
    principalId: user_object_id
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '7f951dda-4ed3-4680-a7ca-43fe172d538d'
    )
  }
}

resource acrpush_user_role_assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().subscriptionId, user_object_id, 'AcrPush')
  scope: container_registry
  properties: {
    principalId: user_object_id
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '8311e382-0749-4cb8-b61a-304f252e45ec'
    )
  }
}

resource storageblobdatacontributor_role_assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().subscriptionId, managed_identity.name, 'StorageBlobDataContributor')
  scope: storage_account
  properties: {
    principalId: managed_identity.properties.principalId
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
    )
  }
}

resource storageblobdatacontributor_user_role_assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().subscriptionId, user_object_id, 'StorageBlobDataContributor')
  scope: storage_account
  properties: {
    principalId: user_object_id
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
    )
  }
}

// create aml workspace
resource aml_workspace 'Microsoft.MachineLearningServices/workspaces@2024-04-01' = {
  name: prefix
  location: location
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    friendlyName: prefix
    applicationInsights: app_insights.id
    containerRegistry: container_registry.id
    description: 'Azure Machine Learning workspace'
    keyVault: key_vault.id
    storageAccount: storage_account.id
    managedNetwork: {
      isolationMode: 'Disabled'
    }
    enableDataIsolation: false
  }
}

// resource storageblobdatacontributor_aml_role_assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
//   name: guid(subscription().subscriptionId, aml_workspace.name, 'StorageBlobDataContributor')
//   scope: storage_account
//   properties: {
//     principalId: aml_workspace.identity.principalId
//     roleDefinitionId: subscriptionResourceId(
//       'Microsoft.Authorization/roleDefinitions',
//       'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
//     )
//   }
// }

// create aml workspace datasource
resource aml_workspace_input_datastore 'Microsoft.MachineLearningServices/workspaces/datastores@2024-04-01' = {
  parent: aml_workspace
  name: 'amljobinput'
  properties: {
    description: 'AML Job Input'
    datastoreType: 'AzureBlob'
    credentials: {
      credentialsType: 'None'
    }
    subscriptionId: subscription().subscriptionId
    resourceGroup: resourceGroup().name
    accountName: storage_account.name
    containerName: storage_container_job_input.name
    serviceDataAccessAuthIdentity: 'WorkspaceSystemAssignedIdentity'
  }
}

resource aml_workspace_output_datastore 'Microsoft.MachineLearningServices/workspaces/datastores@2024-04-01' = {
  parent: aml_workspace
  name: 'amljoboutput'
  properties: {
    description: 'AML Job Output'
    datastoreType: 'AzureBlob'
    credentials: {
      credentialsType: 'None'
    }
    subscriptionId: subscription().subscriptionId
    resourceGroup: resourceGroup().name
    accountName: storage_account.name
    containerName: storage_container_job_output.name
    serviceDataAccessAuthIdentity: 'WorkspaceSystemAssignedIdentity'
  }
}

// create aml compute cluster
resource aml_compute_cluster 'Microsoft.MachineLearningServices/workspaces/computes@2024-04-01' = {
  parent: aml_workspace
  name: 'aml-compute-cluster'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managed_identity.id}': {}
    }
  }
  properties: {
    computeType: 'AmlCompute'
    computeLocation: location
    description: 'VNET integrated compute cluster'
    properties: {
      scaleSettings: {
        minNodeCount: 0
        maxNodeCount: 1
        nodeIdleTimeBeforeScaleDown: 'PT120S'
      }
      subnet: {
        id: vnet.properties.subnets[2].id
      }
      osType: 'Linux'
      vmPriority: 'Dedicated'
      vmSize: 'STANDARD_D2_V2'
    }
  }
}

output aml_storage_name string = storage_account.name
output aml_id string = aml_workspace.id
output aml_tenant_id string = subscription().tenantId
output aml_workspace_name string = aml_workspace.name
output aml_compute_name string = aml_compute_cluster.name
output aml_job_input_datastore string = aml_workspace_input_datastore.name
output aml_job_output_datastore string = aml_workspace_output_datastore.name
output upload_container_name string = storage_container_job_input.name
output upload_storage_url string = storage_account.properties.primaryEndpoints.blob
