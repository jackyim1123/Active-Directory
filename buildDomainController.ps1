<# Notes:

Goal - Create a domain controller and populate with OUs, Groups, and Users.

This script must be run after prepDomainController.ps1.

#>

<#
Specify the configuration to be applied to the server.  This section
defines which configurations you're interested in managing.
#>

configuration buildDomainController
{
    Import-DscResource -ModuleName xComputerManagement -ModuleVersion 3.2.0.0
    Import-DscResource -ModuleName xNetworking -ModuleVersion 5.4.0.0
    Import-DscResource -ModuleName xDnsServer -ModuleVersion 1.9.0.0
    Import-DscResource -ModuleName xActiveDirectory -ModuleVersion 2.16.0.0
    Import-DscResource -ModuleName xAdcsDeployment -ModuleVersion 1.4.0.0

    Node localhost
    {
        LocalConfigurationManager {
            ActionAfterReboot = "ContinueConfiguration"
            ConfigurationMode = "ApplyOnly"
            RebootNodeIfNeeded = $true
        }
  
        xIPAddress NewIPAddress {
            IPAddress = $node.IPAddressCIDR
            InterfaceAlias = $node.InterfaceAlias
            AddressFamily = "IPV4"
        }

        xDefaultGatewayAddress NewIPGateway {
            Address = $node.GatewayAddress
            InterfaceAlias = $node.InterfaceAlias
            AddressFamily = "IPV4"
            DependsOn = "[xIPAddress]NewIPAddress"
        }

        xDnsServerAddress PrimaryDNSClient {
            Address        = $node.DNSAddress
            InterfaceAlias = $node.InterfaceAlias
            AddressFamily = "IPV4"
            DependsOn = "[xDefaultGatewayAddress]NewIPGateway"
        }

        User Administrator {
            Ensure = "Present"
            UserName = "Administrator"
            Password = $Cred
            DependsOn = "[xDnsServerAddress]PrimaryDNSClient"
        }

        xComputer NewComputerName {
            Name = $node.ThisComputerName
            DependsOn = "[User]Administrator"
        }

        WindowsFeature DNSInstall {
            Ensure = "Present"
            Name = "DNS"
            DependsOn = "[xComputer]NewComputerName"
        }

        xDnsServerPrimaryZone addForwardZoneCompanyLdapTest {
            Ensure = "Present"
            Name = $node.DomainName
            DynamicUpdate = "NonsecureAndSecure"
            DependsOn = "[WindowsFeature]DNSInstall"
        }

        # NOTE: Add reverse AD Zone based on your network config
        xDnsServerPrimaryZone addReverseADZone20Net {
            Ensure = "Present"
            Name = "20.168.192.in-addr.arpa"
            DynamicUpdate = "NonsecureAndSecure"
            DependsOn = "[WindowsFeature]DNSInstall"
        }

        xDnsServerPrimaryZone addReverseADZone10Net {
            Ensure = "Present"
            Name = "10.168.192.in-addr.arpa"
            DynamicUpdate = "NonsecureAndSecure"
            DependsOn = "[WindowsFeature]DNSInstall"
        }

        WindowsFeature ADDSInstall {
            Ensure = "Present"
            Name = "AD-Domain-Services"
            DependsOn = "[xDnsServerPrimaryZone]addForwardZoneCompanyLdapTest"
        }

        WindowsFeature ADToolsInstall {
            Ensure = "Present"
            Name = "RSAT-AD-Tools"
            IncludeAllSubFeature = $true
            DependsOn = "[xDnsServerPrimaryZone]addForwardZoneCompanyLdapTest"
        }

        WindowsFeature DNSServerInstall {
            Ensure = "Present"
            Name = "RSAT-DNS-Server"
            DependsOn = "[xDnsServerPrimaryZone]addForwardZoneCompanyLdapTest"
        }

        xADDomain FirstDC {
            DomainName = $node.DomainName
            DomainAdministratorCredential = $domainCred
            SafemodeAdministratorPassword = $domainCred
            DatabasePath = $node.DCDatabasePath
            LogPath = $node.DCLogPath
            SysvolPath = $node.SysvolPath 
            DependsOn = "[WindowsFeature]ADDSInstall"
        }

        # Add OUs, Users and Groups(depend on Users)
        $ADConfigs = "$PSScriptRoot\AD-Configs"
        $OUs = (Get-Content $ADConfigs\AD-OUs.json | ConvertFrom-Json)
        $Users = (Get-Content $ADConfigs\AD-Users.json | ConvertFrom-Json)
        $Groups = (Get-Content $ADConfigs\AD-Groups.json | ConvertFrom-Json)

        # OUs
        foreach ($OU in $OUs) {
            xADOrganizationalUnit $OU.Name {
                Path = $node.DomainDN
                Name = $OU.Name
                Description = $OU.Description
                ProtectedFromAccidentalDeletion = $False
                Ensure = "Present"
                DependsOn = "[xADDomain]FirstDC"
            }
        }
        
        # Users
        foreach ($User in $Users) {
            xADUser $User.SamAccountName {
                DomainName = $node.DomainName
                Path = $User.DistinguishedName.Split(",", 2)[1]
                UserName = $User.SamAccountName
                GivenName = $User.GivenName
                Surname = $User.Surename
                CommonName = $User.Name
                DisplayName = $User.DisplayName
                Description = $User.Description
                Department = $User.Department
                Enabled = $true
                Password = $Cred
                DomainAdministratorCredential = $Cred
                PasswordNeverExpires = $true
                DependsOn = "[xADDomain]FirstDC"
            }
        }

        # Groups
        foreach ($Group in $Groups) {
            xADGroup $Group.Name {
                GroupName = $Group.Name
                Path = $Group.DistinguishedName.Split(",", 2)[1]
                Category = $Group.GroupCategory
                GroupScope = $Group.GroupScope
                Members = $Group.Members
                DependsOn = "[xADDOmain]FirstDC"
            }
        }

        # Install ADCS feature
        WindowsFeature ADCSInstall {
            Ensure = "Present"
            Name = "ADCS-Cert-Authority"
            DependsOn = "[xADDomain]FirstDC"
        }

        # Install ADCS Tools feature
        ## Hack to fix DependsOn with hypens "bug" :(
        foreach ($feature in @(
                'RSAT-ADCS',
                'RSAT-ADCS-Mgmt'
        )) {
            WindowsFeature $feature.Replace('-', '') {
                Ensure = "Present"
                Name = $feature
                IncludeAllSubFeature = $False
                DependsOn = "[xADDomain]FirstDC"
            }
        }

        xWaitForADDomain WaitForADADCSRole {
            DomainName = $node.DomainName
            RetryIntervalSec = '30'
            RetryCount = '10'
            DomainUserCredential = $Cred
            DependsOn = '[WindowsFeature]ADCSInstall'
        }
        
        # Configure Certificate Service
        xAdcsCertificationAuthority ADCSConfig
        {
            Ensure = 'Present'
            CAType = $DomainConfig.CAType
            Credential = $Cred
            CryptoProviderName = $DomainConfig.CryptoProviderName
            HashAlgorithmName = $DomainConfig.HashAlgorithmName
            KeyLength = $DomainConfig.KeyLength
            ValidityPeriod = $DomainConfig.ValidityPeriod
            ValidityPeriodUnits = $DomainConfig.ValidityPeriodUnits
            CACommonName = $DomainConfig.CACommonName
            CADistinguishedNameSuffix = $DomainConfig.CADistinguishedNameSuffix
            DatabaseDirectory = $DomainConfig.DatabaseDirectory
            LogDirectory = $DomainConfig.LogDirectory
            DependsOn = '[WindowsFeature]ADCSInstall'
        }

    }
}

<#
Specify values for the configurations you're interested in managing.
See in the configuration above how variables are used to reference values listed here.
#>

$ADConfigs = "$PSScriptRoot\AD-Configs"
$DomainConfig = (Get-Content $ADConfigs\AD-DomainConfig.json | ConvertFrom-Json)

$ConfigData = @{
    AllNodes = @(
        @{
            Nodename = "localhost"
            ThisComputerName = $DomainConfig.ThisComputerName
            IPAddressCIDR = $DomainConfig.IPAddressCIDR
            DNSAddress = $DomainConfig.DNSAddress
            GatewayAddress = $DomainConfig.GatewayAddress
            InterfaceAlias = $DomainConfig.InterfaceAlias
            DomainName = $DomainConfig.DomainName
            DomainDN = $DomainConfig.DomainDN
            DCDatabasePath = $DomainConfig.DCDatabasePath
            DCLogPath = $DomainConfig.DCLogPath
            SysvolPath = $DomainConfig.SysvolPath

            PSDscAllowPlainTextPassword = $true
            PSDscAllowDomainUser = $true
        }
    )
}

<#
Lastly, prompt for the necessary username and password combinations, then
compile the configuration, and then instruct the server to execute that
configuration against the settings on this local server.
#>

$DomainAdministrator = $DomainConfig.DomainLogonName + "\Administrator"
$domainCred = Get-Credential -UserName $DomainAdministrator -Message "Please enter a new password for Domain Administrator."
$Cred = Get-Credential -UserName Administrator -Message "Please enter a new password for Local Administrator and other accounts."

BuildDomainController -ConfigurationData $ConfigData

Set-DSCLocalConfigurationManager -Path .\buildDomainController –Verbose
Start-DscConfiguration -Wait -Force -Path .\buildDomainController -Verbose