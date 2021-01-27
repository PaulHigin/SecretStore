@{
    ModuleVersion = '1.0'
    RootModule = 'Microsoft.PowerShell.SecretStore.Extension.psm1'
    RequiredAssemblies = '../Microsoft.PowerShell.SecretStore.dll'
    FunctionsToExport = @('Set-Secret','Set-SecretInfo','Get-Secret','Remove-Secret','Get-SecretInfo','Test-SecretVault')
}
