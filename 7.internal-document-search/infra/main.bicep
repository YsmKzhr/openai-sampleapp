targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

param appServicePlanName string = ''
param backendServiceName string = ''
param resourceGroupName string = ''

param searchServiceName string = ''
param searchServiceResourceGroupName string = ''
param searchServiceResourceGroupLocation string = location

param searchServiceSkuName string = 'standard'
param searchIndexName string = 'gptkbindex'

param storageAccountName string = ''
param storageResourceGroupName string = ''
param storageResourceGroupLocation string = location
param storageContainerName string = 'content'

param openAiServiceName string = ''
param openAiResourceGroupName string = ''
param openAiResourceGroupLocation string = location

param openAiSkuName string = 'S0'

param openAiDavinciDeploymentName string = 'davinci'
param openAiGpt35TurboDeploymentName string = 'chat'
param openAiGpt4DeploymentName string = ''
param openAiGpt432kDeploymentName string = ''
param openAiApiVersion string = '2023-05-15'


param formRecognizerServiceName string = ''
param formRecognizerResourceGroupName string = ''
param formRecognizerResourceGroupLocation string = location

param formRecognizerSkuName string = 'S0'

param gptDeploymentName string = 'davinci'
param gptModelName string = 'text-davinci-003'
param chatGptDeploymentName string = 'chat'
param chatGptModelName string = 'gpt-35-turbo'

param cosmosDbDatabaseName string = 'ChatHistory'
param cosmosDbContainerName string = 'Prompts'


param vnetLocation string = location

param privateEndpointLocation string = location

@description('Id of the user or app to assign application roles')
param principalId string = ''

var abbrs = loadJsonContent('abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location, 'v1'))
var tags = { 'azd-env-name': environmentName }

// Organize resources in a resource group
resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

resource openAiResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' existing = if (!empty(openAiResourceGroupName)) {
  name: !empty(openAiResourceGroupName) ? openAiResourceGroupName : resourceGroup.name
}

resource formRecognizerResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' existing = if (!empty(formRecognizerResourceGroupName)) {
  name: !empty(formRecognizerResourceGroupName) ? formRecognizerResourceGroupName : resourceGroup.name
}

resource searchServiceResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' existing = if (!empty(searchServiceResourceGroupName)) {
  name: !empty(searchServiceResourceGroupName) ? searchServiceResourceGroupName : resourceGroup.name
}

resource storageResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' existing = if (!empty(storageResourceGroupName)) {
  name: !empty(storageResourceGroupName) ? storageResourceGroupName : resourceGroup.name
}

module cosmosDb 'core/db/cosmosdb.bicep' = {
  name: 'cosmosdb'
  scope: resourceGroup
  params: {
    name: '${abbrs.documentDBDatabaseAccounts}${resourceToken}'
    location: location
    tags: union(tags, { 'azd-service-name': 'cosmosdb' })
    cosmosDbDatabaseName: cosmosDbDatabaseName
    cosmosDbContainerName: cosmosDbContainerName
  }
}


// Create an App Service Plan to group applications under the same payment plan and SKU
module appServicePlan 'core/host/appserviceplan.bicep' = {
  name: 'appserviceplan'
  scope: resourceGroup
  params: {
    name: !empty(appServicePlanName) ? appServicePlanName : '${abbrs.webServerFarms}${resourceToken}'
    location: location
    tags: tags
    sku: {
      name: 'S1'
      capacity: 1
    }
    kind: 'linux'
  }
}

// The application frontend
module backend 'core/host/appservice.bicep' = {
  name: 'web'
  scope: resourceGroup
  params: {
    name: !empty(backendServiceName) ? backendServiceName : '${abbrs.webSitesAppService}backend-${resourceToken}'
    location: location
    tags: union(tags, { 'azd-service-name': 'backend' })
    appServicePlanId: appServicePlan.outputs.id
    runtimeName: 'python'
    runtimeVersion: '3.10'
    scmDoBuildDuringDeployment: true
    managedIdentity: true
    applicationInsightsName: !empty(backendServiceName) ? backendServiceName : '${abbrs.webSitesAppService}backend-${resourceToken}'
    appSettings: {
      AZURE_STORAGE_ACCOUNT: storage.outputs.name
      AZURE_STORAGE_CONTAINER: storageContainerName
      AZURE_OPENAI_SERVICE: openAi.outputs.name
      AZURE_SEARCH_INDEX: searchIndexName
      AZURE_SEARCH_SERVICE: searchService.outputs.name
      AZURE_OPENAI_DAVINCI_DEPLOYMENT: gptDeploymentName
      AZURE_OPENAI_GPT_35_TURBO_DEPLOYMENT: chatGptDeploymentName
      AZURE_OPENAI_GPT_4_32K_DEPLOYMENT: ''
      AZURE_OPENAI_GPT_4_DEPLOYMENT: ''
      AZURE_OPENAI_API_VERSION: '2023-05-15'
      AZURE_COSMOSDB_CONTAINER: cosmosDbContainerName
      AZURE_COSMOSDB_DATABASE: cosmosDbDatabaseName
      AZURE_COSMOSDB_ENDPOINT: cosmosDb.outputs.endpoint
    }
  }
}

module openAi 'core/ai/cognitiveservices.bicep' = {
  name: 'openai'
  scope: openAiResourceGroup
  params: {
    name: !empty(openAiServiceName) ? openAiServiceName : '${abbrs.cognitiveServicesAccounts}${resourceToken}'
    location: openAiResourceGroupLocation
    tags: tags
    sku: {
      name: openAiSkuName
    }
    deployments: [
      {
        name: gptDeploymentName
        model: {
          format: 'OpenAI'
          name: gptModelName
          version: '1'
        }
        scaleSettings: {
          scaleType: 'Standard'
        }
      }
      {
        name: chatGptDeploymentName
        model: {
          format: 'OpenAI'
          name: chatGptModelName
          version: '0301'
        }
        scaleSettings: {
          scaleType: 'Standard'
        }
      }
    ]
  }
}

module formRecognizer 'core/ai/cognitiveservices.bicep' = {
  name: 'formrecognizer'
  scope: formRecognizerResourceGroup
  params: {
    name: !empty(formRecognizerServiceName) ? formRecognizerServiceName : '${abbrs.cognitiveServicesFormRecognizer}${resourceToken}'
    kind: 'FormRecognizer'
    location: formRecognizerResourceGroupLocation
    tags: tags
    sku: {
      name: formRecognizerSkuName
    }
  }
}

module searchService 'core/search/search-services.bicep' = {
  name: 'search-service'
  scope: searchServiceResourceGroup
  params: {
    name: !empty(searchServiceName) ? searchServiceName : 'gptkb-${resourceToken}'
    location: searchServiceResourceGroupLocation
    tags: tags
    authOptions: {
      aadOrApiKey: {
        aadAuthFailureMode: 'http401WithBearerChallenge'
      }
    }
    sku: {
      name: searchServiceSkuName
    }
    semanticSearch: 'free'
  }
}

module storage 'core/storage/storage-account.bicep' = {
  name: 'storage'
  scope: storageResourceGroup
  params: {
    name: !empty(storageAccountName) ? storageAccountName : '${abbrs.storageStorageAccounts}${resourceToken}'
    location: storageResourceGroupLocation
    tags: tags
    publicNetworkAccess: 'Enabled'
    sku: {
      name: 'Standard_ZRS'
    }
    deleteRetentionPolicy: {
      enabled: true
      days: 2
    }
    containers: [
      {
        name: storageContainerName
        publicAccess: 'None'
      }
    ]
  }
}

// USER ROLES
module openAiRoleUser 'core/security/role.bicep' = {
  scope: openAiResourceGroup
  name: 'openai-role-user'
  params: {
    principalId: principalId
    roleDefinitionId: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
    principalType: 'User'
  }
}

module formRecognizerRoleUser 'core/security/role.bicep' = {
  scope: formRecognizerResourceGroup
  name: 'formrecognizer-role-user'
  params: {
    principalId: principalId
    roleDefinitionId: 'a97b65f3-24c7-4388-baec-2e87135dc908'
    principalType: 'User'
  }
}

module storageRoleUser 'core/security/role.bicep' = {
  scope: storageResourceGroup
  name: 'storage-role-user'
  params: {
    principalId: principalId
    roleDefinitionId: '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
    principalType: 'User'
  }
}

module storageContribRoleUser 'core/security/role.bicep' = {
  scope: storageResourceGroup
  name: 'storage-contribrole-user'
  params: {
    principalId: principalId
    roleDefinitionId: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
    principalType: 'User'
  }
}

module searchRoleUser 'core/security/role.bicep' = {
  scope: searchServiceResourceGroup
  name: 'search-role-user'
  params: {
    principalId: principalId
    roleDefinitionId: '1407120a-92aa-4202-b7e9-c0e197c71c8f'
    principalType: 'User'
  }
}

module searchContribRoleUser 'core/security/role.bicep' = {
  scope: searchServiceResourceGroup
  name: 'search-contrib-role-user'
  params: {
    principalId: principalId
    roleDefinitionId: '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
    principalType: 'User'
  }
}

// SYSTEM IDENTITIES
module openAiRoleBackend 'core/security/role.bicep' = {
  scope: openAiResourceGroup
  name: 'openai-role-backend'
  params: {
    principalId: backend.outputs.identityPrincipalId
    roleDefinitionId: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
    principalType: 'ServicePrincipal'
  }
}

module storageRoleBackend 'core/security/role.bicep' = {
  scope: storageResourceGroup
  name: 'storage-role-backend'
  params: {
    principalId: backend.outputs.identityPrincipalId
    roleDefinitionId: '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
    principalType: 'ServicePrincipal'
  }
}

module searchRoleBackend 'core/security/role.bicep' = {
  scope: searchServiceResourceGroup
  name: 'search-role-backend'
  params: {
    principalId: backend.outputs.identityPrincipalId
    roleDefinitionId: '1407120a-92aa-4202-b7e9-c0e197c71c8f'
    principalType: 'ServicePrincipal'
  }
}

// ===================== create private networks =====================
module vnet 'core/network/vnet.bicep' = {
  name: 'vnet'
  scope: resourceGroup
  params: {
    name: 'vnet'
    location: vnetLocation
    addressPrefixes: ['10.0.0.0/16']
  }
}

module privateEndpointSubnet 'core/network/subnet.bicep' = {
  name: 'private-endpoint-subnet'
  scope: resourceGroup
  params: {
    existVnetName: vnet.outputs.name
    name: 'private-endpoint-subnet'
    addressPrefix: '10.0.0.0/24'
  }
}

module storagePrivateEndopoint 'core/network/privateEndpoint.bicep' = {
  name: 'storage-private-endpoint'
  scope: resourceGroup
  params: {
    location: privateEndpointLocation
    name: '${storage.outputs.name}-endpoint'
    subnetId: privateEndpointSubnet.outputs.id
    privateLinkServiceId: storage.outputs.id
    privateLinkServiceGroupIds: ['Blob']
  }
}

module searchServicePrivateEndopoint 'core/network/privateEndpoint.bicep' = {
  name: 'search-service-private-endpoint'
  scope: resourceGroup
  params: {
    location: privateEndpointLocation
    name: '${searchService.outputs.name}-endpoint'
    subnetId: privateEndpointSubnet.outputs.id
    privateLinkServiceId: searchService.outputs.id
    privateLinkServiceGroupIds: ['searchService']
  }
}

module oepnaiPrivateEndopoint 'core/network/privateEndpoint.bicep' = {
  name: 'openai-service-private-endpoint'
  scope: resourceGroup
  params: {
    location: privateEndpointLocation
    name: '${openAi.outputs.name}-endpoint'
    subnetId: privateEndpointSubnet.outputs.id
    privateLinkServiceId: openAi.outputs.id
    privateLinkServiceGroupIds: ['account']
  }
}

module formRecognizerPrivateEndopoint 'core/network/privateEndpoint.bicep' = {
  name: 'form-recognizer-private-endpoint'
  scope: resourceGroup
  params: {
    location: privateEndpointLocation
    name: '${formRecognizer.outputs.name}-endpoint'
    subnetId: privateEndpointSubnet.outputs.id
    privateLinkServiceId: formRecognizer.outputs.id
    privateLinkServiceGroupIds: ['account']
  }
}

output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output AZURE_RESOURCE_GROUP string = resourceGroup.name

output AZURE_OPENAI_SERVICE string = openAi.outputs.name
output AZURE_OPENAI_RESOURCE_GROUP string = openAiResourceGroup.name
output AZURE_OPENAI_DAVINCI_DEPLOYMENT string = openAiDavinciDeploymentName
output AZURE_OPENAI_GPT_35_TURBO_DEPLOYMENT string = openAiGpt35TurboDeploymentName
output AZURE_OPENAI_GPT_4_DEPLOYMENT string = openAiGpt4DeploymentName
output AZURE_OPENAI_GPT_4_32K_DEPLOYMENT string = openAiGpt432kDeploymentName
output AZURE_OPENAI_API_VERSION string = openAiApiVersion

output AZURE_FORMRECOGNIZER_SERVICE string = formRecognizer.outputs.name
output AZURE_FORMRECOGNIZER_RESOURCE_GROUP string = formRecognizerResourceGroup.name

output AZURE_SEARCH_INDEX string = searchIndexName
output AZURE_SEARCH_SERVICE string = searchService.outputs.name
output AZURE_SEARCH_SERVICE_RESOURCE_GROUP string = searchServiceResourceGroup.name

output AZURE_STORAGE_ACCOUNT string = storage.outputs.name
output AZURE_STORAGE_CONTAINER string = storageContainerName
output AZURE_STORAGE_RESOURCE_GROUP string = storageResourceGroup.name

output AZURE_COSMOSDB_ENDPOINT string = cosmosDb.outputs.endpoint
output AZURE_COSMOSDB_DATABASE string = cosmosDb.outputs.databaseName
output AZURE_COSMOSDB_CONTAINER string = cosmosDb.outputs.containerName

output AZURE_COSMOSDB_ACCOUNT string = cosmosDb.outputs.accountName
output AZURE_COSMOSDB_RESOURCE_GROUP string = resourceGroup.name

output BACKEND_IDENTITY_PRINCIPAL_ID string = backend.outputs.identityPrincipalId
output BACKEND_URI string = backend.outputs.uri
output APPLICATIONINSIGHTS_CONNECTION_STRING string = backend.outputs.applicationInsightsConnectionString