<# Notes:

Goal - Prepare the server by connecting to the gallery,
installing the package provider, and installing the modules
required by the configuration(Online/Offline(Default)). Note that the modules to be installed
are versioned to protect against future breaking changes.

#>
#Requires -RunAsAdministrator

# Online installation
# Requires Internet, GE Proxy and Certificate well configured
# Get-PackageSource -Name PSGallery | Set-PackageSource -Trusted -Force -ForceBootstrap

# Install-PackageProvider -Name NuGet -Force

# Install-Module xComputerManagement -RequiredVersion 3.2.0.0 -Force
# Install-Module xNetworking -RequiredVersion 5.4.0.0 -Force
# Install-Module xDnsServer -RequiredVersion 1.9.0.0 -Force
# Install-Module xActiveDirectory -RequiredVersion 2.16.0.0 -Force

# Offline installation
$SourcePath = $PSScriptRoot
$DestinationPath = 'C:\Program Files\WindowsPowerShell\Modules'

foreach ($module in @(
    "xActiveDirectory",
    "xAdcsDeployment",
    "xComputerManagement",
    "xDnsServer",
    "xNetworking"
)) {
    Write-Host -ForegroundColor Cyan "Installing $module to $DestinationPath..."
    Copy-Item -Path "$SourcePath\Modules\$module" -Destination "$DestinationPath" -Recurse -Force
}

Write-Host -ForegroundColor Green "You may now execute '.\buildDomainController.ps1'"
