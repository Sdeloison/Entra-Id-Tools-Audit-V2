@description('Azure region for the audit resources.')
param location string = resourceGroup().location
@description('Globally unique storage account name (3-24 lowercase letters/numbers).')
@minLength(3)
@maxLength(24)
param storageAccountName string = 'entraaudit${uniqueString(resourceGroup().id)}'
@description('Globally unique App Service name.')
param dashboardAppName string = 'entra-audit-${uniqueString(resourceGroup().id)}'
@description('Private blob container for versioned audit reports.')
param reportContainerName string = 'audit-reports'

var tags = {
  EntraTenantAudit: 'EntraTenantAudit'
  dataClassification: 'Sensitive'
}
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
var storageBlobDataReaderRoleId = '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'

resource automationIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'entra-audit-collector'
  location: location
  tags: tags
}

resource automation 'Microsoft.Automation/automationAccounts@2023-11-01' = {
  name: 'entra-audit-${uniqueString(resourceGroup().id)}'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${automationIdentity.id}': {}
    }
  }
  properties: {
    sku: {
      name: 'Basic'
    }
    publicNetworkAccess: true
  }
  tags: tags
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_GRS'
  }
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'None'
      defaultAction: 'Allow'
    }
  }
  tags: tags
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
}

resource reportContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: reportContainerName
  properties: {
    publicAccess: 'None'
  }
}

resource collectorBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(reportContainer.id, automationIdentity.id, storageBlobDataContributorRoleId)
  scope: reportContainer
  properties: {
    principalId: automationIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
  }
}

resource dashboardPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: 'entra-audit-dashboard-plan'
  location: location
  kind: 'linux'
  sku: {
    name: 'B1'
    tier: 'Basic'
    capacity: 1
  }
  properties: {
    reserved: true
  }
  tags: tags
}

resource dashboard 'Microsoft.Web/sites@2023-12-01' = {
  name: dashboardAppName
  location: location
  kind: 'app,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: dashboardPlan.id
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    siteConfig: {
      linuxFxVersion: 'NODE|22-lts'
      alwaysOn: true
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      http20Enabled: true
      appSettings: [
        { name: 'SCM_DO_BUILD_DURING_DEPLOYMENT', value: 'true' }
        { name: 'AZURE_STORAGE_ACCOUNT', value: storage.name }
        { name: 'AZURE_STORAGE_CONTAINER', value: reportContainerName }
        { name: 'DASHBOARD_TENANT_ID', value: '' }
        { name: 'DASHBOARD_CLIENT_ID', value: '' }
        { name: 'DASHBOARD_AUDIENCE', value: '' }
        { name: 'DASHBOARD_ALLOWED_GROUP_ID', value: '' }
      ]
    }
  }
  tags: tags
}

resource dashboardBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(reportContainer.id, dashboard.id, storageBlobDataReaderRoleId)
  scope: reportContainer
  properties: {
    principalId: dashboard.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataReaderRoleId)
  }
}

output automationAccountName string = automation.name
output automationIdentityClientId string = automationIdentity.properties.clientId
output automationIdentityPrincipalId string = automationIdentity.properties.principalId
output storageAccountName string = storage.name
output reportContainerName string = reportContainer.name
output dashboardUrl string = 'https://${dashboard.properties.defaultHostName}'
output dashboardPrincipalId string = dashboard.identity.principalId
