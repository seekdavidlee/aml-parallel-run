param location string
@minLength(5)
param prefix string
param ip_list string
param user_object_id string

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
      bypass: 'None' // This is not required because we will be creating a network rule and specifically assigning AML to storage for access
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

// create azure key vault
resource key_vault 'Microsoft.KeyVault/vaults@2024-04-01-preview' = {
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

resource keyvaultsecretsofficer_user_role_assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().subscriptionId, user_object_id, 'KeyVaultSecretsOfficer')
  scope: key_vault
  properties: {
    principalId: user_object_id
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
    )
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
  name: '${prefix}-aml'
  location: location
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    friendlyName: prefix
    applicationInsights: app_insights.id
    containerRegistry: container_registry.id
    description: 'Azure Machine Learning workspace for running parallel jobs'
    keyVault: key_vault.id
    storageAccount: storage_account.id
    managedNetwork: {
      isolationMode: 'AllowOnlyApprovedOutbound'
      outboundRules: {
        table_rule: {
          type: 'PrivateEndpoint'
          destination: { serviceResourceId: storage_account.id, sparkEnabled: false, subresourceTarget: 'table' }
        }
        queue_rule: {
          type: 'PrivateEndpoint'
          destination: { serviceResourceId: storage_account.id, sparkEnabled: false, subresourceTarget: 'queue' }
        }
      }
    }
    enableDataIsolation: false
  }
}

// resource keyvaultcontributor_user_role_assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
//   name: guid(subscription().subscriptionId, user_object_id, 'KeyVaultContributor')
//   scope: key_vault
//   properties: {
//     principalId: aml_workspace.identity.principalId
//     roleDefinitionId: subscriptionResourceId(
//       'Microsoft.Authorization/roleDefinitions',
//       'f25e0fa2-a7c8-4377-a976-54943a77a395'
//     )
//   }
// }

// resource keyvaultadministrator_user_role_assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
//   name: guid(subscription().subscriptionId, user_object_id, 'KeyVaultAdministrator')
//   scope: key_vault
//   properties: {
//     principalId: aml_workspace.identity.principalId
//     roleDefinitionId: subscriptionResourceId(
//       'Microsoft.Authorization/roleDefinitions',
//       '00482a5a-887f-4fb3-b363-3b7fe8e74483'
//     )
//   }
// }

// resource allow_aml_queue_rule 'Microsoft.MachineLearningServices/workspaces/outboundRules@2024-04-01' = {
//   parent: aml_workspace
//   name: 'allow-aml-queue-rule'
//   properties: {
//     type: 'PrivateEndpoint'
//     destination: {
//       serviceResourceId: storage_account.id
//       sparkEnabled: false
//       subresourceTarget: 'queue'
//     }
//   }
// }

// resource allow_aml_table_rule 'Microsoft.MachineLearningServices/workspaces/outboundRules@2024-04-01' = {
//   parent: aml_workspace
//   name: 'allow-aml-table-rule'
//   properties: {
//     type: 'PrivateEndpoint'
//     destination: {
//       serviceResourceId: storage_account.id
//       sparkEnabled: false
//       subresourceTarget: 'table'
//     }
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
        maxNodeCount: 3
        nodeIdleTimeBeforeScaleDown: 'PT900S' // shut down after 15 mins of inactivity
      }
      enableNodePublicIp: true // there is no need for public IP but this requires workspace to have private endpoint, so we are leaving it as true
      osType: 'Linux'
      vmPriority: 'Dedicated' // improve startup time by using dedicated VMs
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
output key_vault_name string = key_vault.name
output managed_identity_id string = managed_identity.properties.clientId
