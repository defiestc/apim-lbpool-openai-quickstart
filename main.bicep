
var resourceSuffix = uniqueString(subscription().id, resourceGroup().id)
@description('The name of the API Management service instance')
param apiManagementServiceName string = 'apiservice${uniqueString(subscription().id, resourceGroup().id)}'

@description('The pricing tier of this API Management service')
@allowed([
  'Consumption'
  'Developer'
  'Basic'
  'Basicv2'
  'Standard'
  'Standardv2'
  'Premium'
])
param sku string = 'Basicv2'

@description('The instance size of this API Management service.')
@allowed([
  0
  1
  2
])
param skuCount int = 1

@description('Location for all resources.')


param location string = resourceGroup().location
param openAISku string = 'S0'

resource cognitiveServices1 'Microsoft.CognitiveServices/accounts@2021-10-01' = {
  name: 'cog1-${resourceSuffix}'
  location: location
  sku: {
    name: openAISku
  }
  kind: 'OpenAI'  
  properties: {
    apiProperties: {
      statisticsEnabled: false
    }
    customSubDomainName: toLower('cog1-${resourceSuffix}')
  }
}
resource openaidepl1 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01'  =  {
  name: 'openaideploy1'
  parent: cognitiveServices1
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-35-turbo'
      version: '0613'
    }
  }
  sku: {
      name: 'Standard'
      capacity: 10
  }
}

resource cognitiveServices2 'Microsoft.CognitiveServices/accounts@2021-10-01' = {
  name: 'cog2-${resourceSuffix}'
  location: location
  sku: {
    name: openAISku
  }
  kind: 'OpenAI'  
  properties: {
    apiProperties: {
      statisticsEnabled: false
    }
    customSubDomainName: toLower('cog2-${resourceSuffix}')
  }
}
resource openaidepl2 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01'  =  {
  name: 'openaideploy2'
  parent: cognitiveServices2
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-35-turbo'
      version: '0613'
    }
  }
  sku: {
      name: 'Standard'
      capacity: 10
  }
}



resource apiManagementService 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: apiManagementServiceName
  location: location
  sku: {
    name: sku
    capacity: skuCount
  }
  properties: {
    publisherEmail: 'publisher@contoso.com'
    publisherName: 'Contos Publisher'
  }
  identity: {
    type: 'SystemAssigned'
  } 
}


var roleDefinitionID = resourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
resource roleAssignment1 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
    scope: cognitiveServices1
    name: guid(subscription().id, resourceGroup().id, 'cognitiveServices1')
    properties: {
        roleDefinitionId: roleDefinitionID
        principalId: apiManagementService.identity.principalId
        principalType: 'ServicePrincipal'
    }
}
resource roleAssignment2 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: cognitiveServices2
  name: guid(subscription().id, resourceGroup().id, 'cognitiveServices2')
  properties: {
      roleDefinitionId: roleDefinitionID
      principalId: apiManagementService.identity.principalId
      principalType: 'ServicePrincipal'
  }
}


resource api 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  name: 'openai'
  parent: apiManagementService
  properties: {
    apiType: 'http'
    description: 'Azure OpenAI API from API Management'
    displayName: 'OpenAI'
    format: 'openapi-link'
    path: 'openai'
    protocols: [
      'https'
    ]
    subscriptionKeyParameterNames: {
      header: 'api-key'
      query: 'api-key'
    }
    subscriptionRequired: true
    type: 'http'
    value: 'https://raw.githubusercontent.com/Azure/azure-rest-api-specs/main/specification/cognitiveservices/data-plane/AzureOpenAI/inference/stable/2024-02-01/inference.json'
  }
}
resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2021-12-01-preview' = {
  name: 'policy'
  parent: api
  properties: {
    format: 'rawxml'
    value: loadTextContent('policy.xml')
  }
}


resource backendOpenAI1 'Microsoft.ApiManagement/service/backends@2023-05-01-preview' = {
  name: 'backend1'
  parent: apiManagementService
  properties: {
    description: 'backend description'
    url: '${cognitiveServices1.properties.endpoint}/openai'
    protocol: 'http'
    circuitBreaker: {
      rules: [
        {
          failureCondition: {
            count: 3
            errorReasons: [
              'Server errors'
            ]
            interval: 'PT5M'
            statusCodeRanges: [
              {
                min: 429
                max: 429
              }
            ]
          }
          name: 'openAIBreakerRule'
          tripDuration: 'PT1M'
        }
      ]
    }    
  }
}
resource backendOpenAI2 'Microsoft.ApiManagement/service/backends@2023-05-01-preview' = {
  name: 'backend2'
  parent: apiManagementService
  properties: {
    description: 'backend description'
    url: '${cognitiveServices2.properties.endpoint}/openai'
    protocol: 'http'
    circuitBreaker: {
      rules: [
        {
          failureCondition: {
            count: 3
            errorReasons: [
              'Server errors'
            ]
            interval: 'PT5M'
            statusCodeRanges: [
              {
                min: 429
                max: 429
              }
            ]
          }
          name: 'openAIBreakerRule'
          tripDuration: 'PT1M'
        }
      ]
    }    
  }
}


resource backendPoolOpenAI 'Microsoft.ApiManagement/service/backends@2023-05-01-preview' = {
  name: 'openai-backend-pool'
  parent: apiManagementService
  properties: {
    description: 'Load balancer for multiple OpenAI endpoints'
    type: 'Pool'
    pool: {
      services: [
        {
          id: '/backends/${backendOpenAI1.name}'
          priority: 1
          weight: 10
        }
        {
          id: '/backends/${backendOpenAI2.name}'
          priority: 1
          weight: 20
        }]
      
    }
  }
}

resource apimSubscription 'Microsoft.ApiManagement/service/subscriptions@2023-05-01-preview' = {
  name: 'openAISubscriptionName'
  parent: apiManagementService
  properties: {
    allowTracing: true
    displayName: 'Open AI Subscription Description'
    scope: '/apis/${api.id}'
    state: 'active'
  }
}
