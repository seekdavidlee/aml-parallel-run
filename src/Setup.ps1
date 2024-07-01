param (
    [Parameter(Mandatory = $true)][string]$prefix,
    [string]$location = "eastus"
)

$ErrorActionPreference = "Stop"

if (!$prefix) {
    throw "Prefix is required."
}

$groupName = $prefix
If (-Not [bool]((az group exists -n $groupName) -eq 'true')) { az group create --name $groupName --location $location }
if ($LASTEXITCODE -ne 0) {
    throw "Failed to create or verify aml resource group."
}

# Get current IP address
$ipAddress = (Invoke-WebRequest ifconfig.me/ip).Content.Trim()

$userObjectId = az ad signed-in-user show --query id -o tsv

$deploymentName = Get-Date -Format "yyyyMMddHHmmss"
$output = az deployment group create --name $deploymentName `
    --resource-group $groupName `
    --template-file deployments/aml.bicep `
    --parameters location=$location prefix=$prefix ip_list="['$ipAddress']" user_object_id=$userObjectId | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) {
    throw "Failed to deploy the aml resources."
}

$amlWorkspaceName = $output.properties.outputs.aml_workspace_name.value
$amlComputeName = $output.properties.outputs.aml_compute_name.value
$amlJobInputDatastore = $output.properties.outputs.aml_job_input_datastore.value
$amlJobOutputDatastore = $output.properties.outputs.aml_job_output_datastore.value
$uploadContainerName = $output.properties.outputs.upload_container_name.value
$uploadStorageUrl = $output.properties.outputs.upload_storage_url.value
$keyVaultName = $output.properties.outputs.key_vault_name.value
$managedIdentityId = $output.properties.outputs.managed_identity_id.value

# Shows we can access Azure Key Vault from the AML Job
$secretKey1 = [guid]::NewGuid().ToString()
az keyvault secret set --vault-name $keyVaultName --name "SecretKey1" --value $secretKey1
if ($LASTEXITCODE -ne 0) {
    throw "Failed to configure secret to in Azure Key Vault."
}

# Allow AzureML to access the storage account
az storage account network-rule add --account-name $output.properties.outputs.aml_storage_name.value `
    --resource-group $groupName `
    --tenant-id $output.properties.outputs.aml_tenant_id.value `
    --action 'Allow' `
    --resource-id $output.properties.outputs.aml_id.value
if ($LASTEXITCODE -ne 0) {
    throw "Failed to configure AzureML to access the storage account."
}

az ml workspace update --name $amlWorkspaceName --resource-group $groupName --image-build-compute $amlComputeName
if ($LASTEXITCODE -ne 0) {
    throw "Failed to configure AzureML to use compute $amlComputeName."
}

# env file
# Create a new instance of StringBuilder
$stringBuilder = New-Object System.Text.StringBuilder

$subscriptionId = az account show --query id -o tsv
if ($LASTEXITCODE -ne 0) {
    throw "Failed to get subscription id."
}
[void]$stringBuilder.AppendLine("AML_SUBSCRIPTION_ID=$subscriptionId")
[void]$stringBuilder.AppendLine("AML_RESOURCE_GROUP_NAME=$groupName")
[void]$stringBuilder.AppendLine("AML_WORKSPACE_NAME=$amlWorkspaceName")
[void]$stringBuilder.AppendLine("AML_COMPUTE_NAME=$amlComputeName")
[void]$stringBuilder.AppendLine("AML_LOG_LEVEL=DEBUG")
[void]$stringBuilder.AppendLine("AML_IMAGE_NAME=mcr.microsoft.com/azureml/openmpi4.1.0-ubuntu22.04")
[void]$stringBuilder.AppendLine("AML_EXPERIMENT_NAME=TEST_AML_RUN")
[void]$stringBuilder.AppendLine("AML_JOB_CONCURRENCY=1")
[void]$stringBuilder.AppendLine("AML_JOB_INSTANCE_COUNT=1")
[void]$stringBuilder.AppendLine("AML_JOB_INPUT_DATASTORE=$amlJobInputDatastore")
[void]$stringBuilder.AppendLine("AML_JOB_OUTPUT_DATASTORE=$amlJobOutputDatastore")
[void]$stringBuilder.AppendLine("JOB_KEY_VAULT_NAME=$keyVaultName") # This is set as an environment variable in the AML Job
[void]$stringBuilder.AppendLine("JOB_MANAGED_IDENTITY_ID=$managedIdentityId")
[void]$stringBuilder.AppendLine("UPLOAD_CONTAINER_NAME=$uploadContainerName")
[void]$stringBuilder.AppendLine("UPLOAD_STORAGE_URL=$uploadStorageUrl")

Set-Content -Path .env -Value $stringBuilder.ToString() -Force