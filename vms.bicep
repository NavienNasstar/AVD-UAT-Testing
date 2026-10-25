// Entry template (subscription scope): deploys N session hosts into an EXISTING AVD host pool.
// Shared Practice code: it contains NO customer values. Everything customer-specific comes from the
// customer's Azure DevOps variable library, passed in by the pipeline as inline parameters (no .bicepparam files).
//
// Most names are derived from the customer abbreviation (companyPrefix), region and environment,
// so a customer normally only has to supply the REQUIRED values below.
targetScope = 'subscription'

// =====================================================================================
// REQUIRED: the minimum every customer must supply (variable library or run dialog)
// =====================================================================================
@description('Subscription ID the VMs are deployed to.')
param avdSubscriptionID string

@description('Azure region, e.g. uksouth.')
param primaryRegion string

@description('Short region code used in names, e.g. uks.')
param primaryRegionSH string

@description('Customer abbreviation (2-5 letters), e.g. nas. Drives most resource names.')
@minLength(2)
@maxLength(5)
param companyPrefix string

@description('Environment of these session hosts.')
@allowed([
  'uat'
  'prod'
])
param env string

@description('Number of VMs to deploy.')
@minValue(1)
param hostDeployCount int

@description('Number of VMs that already exist. 0 for a new deployment; set to the existing count when adding more so numbering continues.')
@minValue(0)
param currentHostCount int

@description('VM size, e.g. Standard_E8ds_v5.')
param vmSku string

@description('Resource ID of the compute gallery image version to deploy from. The image must not define data disks.')
param imageReference string

@description('Host pool registration token. The pipeline generates it just before deployment.')
@secure()
param hostpoolToken string

@description('How the VMs are joined: domain = Active Directory, entra = Microsoft Entra ID, none = not joined.')
@allowed([
  'domain'
  'entra'
  'none'
])
param joinType string

// =====================================================================================
// OPTIONAL: derived from companyPrefix / region by default. Set a library variable only to override.
// =====================================================================================
@description('Workload used in the VM names, e.g. general, finance.')
param workload string = 'general'

@description('Environment label of the SHARED services (vnet, subnet, key vault, DCR, resource group). UAT and PROD share them, so this is normally prod.')
param sharedInfraEnv string = 'prod'

@description('Existing resource group the VMs are deployed into.')
param resourceGroupName string = 'rg-${companyPrefix}-${primaryRegionSH}-avd-${sharedInfraEnv}'

@description('Name of the EXISTING AVD host pool the VMs register to.')
param hostpoolName string = 'hp-${companyPrefix}-${primaryRegionSH}-${env}'

@description('Computer name prefix, used exactly as written. Empty = <PREFIX>AVD<REGION>- for PROD (NASAVDUKS-1) and <PREFIX>AVD<REGION>-U for UAT (NASAVDUKS-U1).')
param computerNameStem string = ''

@description('Availability zones to spread the VMs over, in order. Empty array = no zone (for regions without zones).')
param availabilityZones array = [
  1
  2
  3
]

// ---- Network ----
@description('Name of the vnet.')
param vnetName string = 'vnet-${companyPrefix}-${primaryRegionSH}-avd-${sharedInfraEnv}'

@description('Subnet the VMs are placed in. It needs outbound internet access (NAT gateway or firewall route).')
param subnetName string = 'snet-${companyPrefix}-${primaryRegionSH}-avd-${sharedInfraEnv}'

@description('Subscription of the vnet.')
param vnetSubscription string = avdSubscriptionID

@description('Resource group of the vnet.')
param vnetRgName string = resourceGroupName

// ---- Key Vault (secret NAMES, never values) ----
@description('Key Vault containing the admin credential secrets.')
param keyvaultName string = 'kv-${companyPrefix}-${primaryRegionSH}-idty-${sharedInfraEnv}'

@description('Resource group of the Key Vault.')
param keyvaultRgName string = 'rg-${companyPrefix}-${primaryRegionSH}-identity-${sharedInfraEnv}'

@description('Subscription of the Key Vault.')
param keyvaultSubscription string = avdSubscriptionID

@description('Name of the Key Vault secret holding the VM admin username.')
param adminUsernameSecretName string = 'adminUsernameSecret'

@description('Name of the Key Vault secret holding the VM admin password.')
param adminPasswordSecretName string = 'adminPasswordSecret'

@description('Name of the Key Vault secret holding the domain join password. Only used when joinType is domain. When not joining a domain it must still name an existing secret, so it defaults to the admin password secret.')
param domainPasswordSecretName string = adminPasswordSecretName

// ---- Domain join (only when joinType is domain) ----
@description('Domain name, e.g. contoso.com.')
param domainName string = ''

@description('OU path for the computer accounts, e.g. OU=AVD,DC=contoso,DC=com.')
param ouPath string = ''

@description('Account used to join the domain, e.g. svc-join@contoso.com.')
param domainUsername string = ''

// ---- Optional features (Practice standards decide the defaults) ----
@description('Create the VMs with Trusted Launch (secure boot + vTPM). Required when the image only supports Trusted Launch.')
param trustedLaunch bool = true

@description('Enable encryption at host. Needs the Microsoft.Compute/EncryptionAtHost feature registered on the subscription.')
param encryptionAtHost bool = false

@description('Install the Azure Monitor Agent and associate the data collection rule.')
param enableAma bool = false

@description('Install the Azure Policy guest configuration extension.')
param enableGuestConfig bool = false

@description('Install the Microsoft Defender for Endpoint extension.')
param enableDefender bool = false

@description('Optional. Full resource ID of an Azure Update Manager maintenance configuration to assign every new VM to. Leave empty if a dynamic scope or Azure Policy does it.')
param maintenanceConfigurationId string = ''

@description('Data collection rule name. Used when enableAma is true.')
param dcrName string = 'MSVMI-${companyPrefix}-win-dcr-${sharedInfraEnv}'

@description('Data collection rule resource group. Used when enableAma is true.')
param dcrRG string = 'rg-${companyPrefix}-${primaryRegionSH}-logging-${sharedInfraEnv}'

@description('Data collection rule subscription. Used when enableAma is true.')
param dcrSub string = avdSubscriptionID

// =====================================================================================
// Derived values (not parameters)
// =====================================================================================
var namingSuffix = '${companyPrefix}-${primaryRegionSH}-avd-${workload}-${env}'
// Windows computer name: <PREFIX>AVD<REGION>-<n> (PROD) or ...-U<n> (UAT). Shortened so the whole name never exceeds 15 characters.
var hostStem = empty(computerNameStem) ? '${toUpper(companyPrefix)}AVD${toUpper(primaryRegionSH)}-${env == 'uat' ? 'U' : ''}' : computerNameStem
var hostNames = [for i in range(0, hostDeployCount): '${take(hostStem, 15 - length(string(i + 1 + currentHostCount)))}${i + 1 + currentHostCount}']
var dcrId = '/subscriptions/${dcrSub}/resourceGroups/${dcrRG}/providers/Microsoft.Insights/dataCollectionRules/${dcrName}'
var subnetId = empty(subnetName) ? virtualNetwork.properties.subnets[0].id : '${virtualNetwork.id}/subnets/${subnetName}'
var tags = {
  Workload: workload
  Env: env
}

resource avdKeyvault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyvaultName
  scope: resourceGroup(keyvaultSubscription, keyvaultRgName)
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2022-07-01' existing = {
  name: vnetName
  scope: resourceGroup(vnetSubscription, vnetRgName)
}

module vm './vm.bicep' = [for i in range(0, hostDeployCount): {
  name: 'vmDeployment-${i + 1 + currentHostCount}'
  scope: resourceGroup(avdSubscriptionID, resourceGroupName)
  params: {
    name: 'vm-${namingSuffix}-${i + 1 + currentHostCount}'
    computerName: hostNames[i]
    nicName: 'nic-${namingSuffix}-${i + 1 + currentHostCount}'
    osDiskName: 'osdisk-${namingSuffix}-${i + 1 + currentHostCount}'
    location: primaryRegion
    vmSize: vmSku
    zone: empty(availabilityZones) ? 0 : availabilityZones[(i + currentHostCount) % length(availabilityZones)]
    imageReference: imageReference
    subnetId: subnetId
    adminUsername: avdKeyvault.getSecret(adminUsernameSecretName)
    adminPassword: avdKeyvault.getSecret(adminPasswordSecretName)
    trustedLaunch: trustedLaunch
    encryptionAtHost: encryptionAtHost
    joinType: joinType
    domainName: domainName
    ouPath: ouPath
    domainUsername: domainUsername
    domainPassword: avdKeyvault.getSecret(domainPasswordSecretName)
    hostpoolName: hostpoolName
    hostpoolToken: hostpoolToken
    enableAma: enableAma
    enableGuestConfig: enableGuestConfig
    enableDefender: enableDefender
    maintenanceConfigurationId: maintenanceConfigurationId
    dcrId: dcrId
    tags: tags
  }
}]
