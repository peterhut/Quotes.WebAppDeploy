<#
 .SYNOPSIS
    Deploys a template to Azure

 .DESCRIPTION
    Deploys an Azure Resource Manager template

 .PARAMETER SubscriptionId
    The subscription id where the template will be deployed.

 .PARAMETER ResourceGroupName
    The resource group where the template will be deployed. Can be the name of an existing or a new resource group.

 .PARAMETER ResourceGroupLocation
    Optional, a resource group location. If specified, will try to create a new resource group in this location. If not specified, assumes resource group is existing.
#>

param(
    
    [Parameter(Mandatory = $True)]
    [string] $SubscriptionId,

    [Parameter(Mandatory = $True)]
    [string] $ResourceGroupName,

    [string]
    $ResourceGroupLocation = "West Europe",

    [string]
    $Type = "small"
)

$ErrorActionPreference = "Stop"
$InformationPreference = "Continue" # Show Write-Information in the script output
$ScriptPath = $(Split-Path $MyInvocation.MyCommand.Path)

# For New-Password function:
. "$ScriptPath\common\UtilityLib.ps1"

$templateFilePath = "$ScriptPath\..\configuration\resource-group\quotes-arm-template.json"
$parametersFilePath = "$ScriptPath\..\configuration\resource-group\parameters-$Type.json"

Write-Host "Ensure you are logged into Azure before running the script.";
# select subscription
Write-Host "Selecting subscription '$SubscriptionId'";
Select-AzureRmSubscription -SubscriptionID $SubscriptionId;

$subscriptionAadTenantId = (Get-AzureRmContext).Subscription.TenantId
$azureAccountId = (Get-AzureRmContext).Account.Id
$azureAccountType = (Get-AzureRmContext).Account.Type

# Ensure the Resource providers are registered:
#$resourceProviders = @("microsoft.insights", "microsoft.sql", "microsoft.storage", "microsoft.web");
# If not uncomment the list and the following script
#foreach ($resourceProvider in $resourceProviders) {            
#    Write-Host "Registering resource provider '$resourceProvider'";
#    $result = Register-AzureRmResourceProvider -ProviderNamespace $resourceProvider;
#}

#Create or check for existing resource group
$resourceGroup = Get-AzureRmResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
if (!$resourceGroup) {
    Write-Host "Resource group '$ResourceGroupName' does not exist. To create a new resource group, please enter a location.";
    if (!$ResourceGroupLocation) {
        $ResourceGroupLocation = Read-Host "ResourceGroupLocation";
    }
    Write-Host "Creating resource group '$ResourceGroupName' in location '$ResourceGroupLocation'";
    New-AzureRmResourceGroup -Name $ResourceGroupName -Location $resourceGroupLocation
}
else {
    Write-Host "Using existing resource group '$ResourceGroupName'";
}

    # generate password and pass to template as parameter
$dbAdminPassword = New-Password 12 ULNS "OLIoli01"
$secureDbAdminPassword = ConvertTo-SecureString -String $dbAdminPassword -AsPlainText -Force

# Start the deployment
Write-Host "Starting deployment...";
$result = New-AzureRmResourceGroupDeployment -Verbose -ResourceGroupName $ResourceGroupName -TemplateFile $templateFilePath -TemplateParameterFile $parametersFilePath -dbAdminPassword $secureDbAdminPassword -aadTenantId $subscriptionAadTenantId;
 
if ($result.ProvisioningState -ne "Succeeded") {
    Write-Error "Resource Group deployment failed. See above for the errors. Final provisioning state: $($result.ProvisioningState)"
}

# Add generated password to the Key Vault
try {
    $kv = (Get-AzureRmKeyVault -ResourceGroupName $ResourceGroupName)[0]
    if ($azureAccountType -eq "ServicePrincipal") {
        # Ensure Service Principal has sufficient permissions to add secret
        Set-AzureRmKeyVaultAccessPolicy -VaultName $kv.VaultName -ServicePrincipalName $azureAccountId -PermissionsToSecrets get, set, list
    }
    else {
        # Running script manually. Assuming current user is part of the ConfigurationManagers AD group
        $configManagersGroupName = "ConfigurationManagers"
        $configManagersGroup = (Get-AzureRmADGroup | where { $_.DisplayName -eq $configManagersGroupName })[0]
        Set-AzureRmKeyVaultAccessPolicy -VaultName $kv.VaultName -ObjectId $configManagersGroup.Id -PermissionsToSecrets get, set, list
    }
    $dbPasswordSecretName = "AzureSQLAdminPassword"
    $secret = Set-AzureKeyVaultSecret -VaultName $kv.VaultName -Name $dbPasswordSecretName -SecretValue $secureDbAdminPassword
    Write-Information "Database Server admin account: cgiadmin. Password stored in Key Vault as secret $($secret.Name) with id $($secret.Id)"  
}
Catch {
    Write-Warning "Failed to store passwords and keys in the Key Vault. Error: $_"
}