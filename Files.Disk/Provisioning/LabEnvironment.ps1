
Configuration CommonServer {
    param (
        [PSCredential]$AdministratorPassword,
        [bool]$IsServiceFabricNode
    )

    Import-DscResource –ModuleName 'PSDesiredStateConfiguration'
    Import-DscResource -ModuleName 'xNetworking' -ModuleVersion '5.0.0.0'
    Import-DscResource -ModuleName 'xRemoteDesktopAdmin' -ModuleVersion '1.1.0.0'
    Import-DscResource -ModuleName 'CredentialManagement' -ModuleVersion '1.0.0.0'

    # Administrator password never expires
    User Administrator {
        Ensure                 = 'Present'
        UserName               = 'Administrator'
        Password               = $AdministratorPassword
        PasswordChangeRequired = $false
        PasswordNeverExpires   = $true
    }

    foreach ($networkAdapter in $Node.NetworkAdapters) {
        $network = $networkAdapter.Network
        if ($networkAdapter.StaticIPAddress) {
            xDhcpClient "DisableDHCP_$($network.Name)" {
                InterfaceAlias     = $network.Name
                AddressFamily      = $network.AddressFamily
                State              = 'Disabled'
            }

            xIPAddress "Network_$($network.Name)" {
                InterfaceAlias     = $network.Name
                AddressFamily      = $network.AddressFamily
                IPAddress          = "$($networkAdapter.StaticIPAddress)/$($network.PrefixLength)"
                DependsOn          = "[xDhcpClient]DisableDHCP_$($network.Name)"
            }

            if ($network.DefaultGateway -and $network.DefaultGateway -ne $networkAdapter.StaticIPAddress) {
                xDefaultGatewayAddress "DefaultGateway_$($network.Name)" {
                    InterfaceAlias     = $network.Name
                    AddressFamily      = $network.AddressFamily
                    Address            = $network.DefaultGateway
                }
            }

            $dnsServerIPAddress = @()
            if ($IsServiceFabricNode -and $networkAdapter.StaticIPAddress) {
                $dnsServerIPAddress += $networkAdapter.StaticIPAddress
            }
            if ($network.DnsServerIPAddress) {
                $dnsServerIPAddress += $network.DnsServerIPAddress
            }
            if ($dnsServerIPAddress) {
                xDnsServerAddress "DnsServerAddress_$($network.Name)" {
                    InterfaceAlias = $network.Name
                    AddressFamily  = $network.AddressFamily
                    Address        = $dnsServerIPAddress
                    DependsOn      = "[xIPAddress]Network_$($network.Name)"
                }
            }
        }
        else {
            xDhcpClient "EnableDHCP_$($network.Name)" {
                InterfaceAlias     = $network.Name
                AddressFamily      = $network.AddressFamily
                State              = 'Enabled'
            }
        }
    }

    xRemoteDesktopAdmin RemoteDesktopSettings {
        Ensure                 = 'Present' 
        UserAuthentication     = 'Secure'
    }
    xFirewall AllowRDP {
        Ensure                 = 'Present'
        Name                   = 'RemoteDesktop-UserMode-In-TCP'
        Enabled                = 'True'
    }

    Registry DoNotOpenServerManagerAtLogon {
        Ensure                 = 'Present'
        Key                    = 'HKLM:\SOFTWARE\Microsoft\ServerManager'
        ValueName              = 'DoNotOpenServerManagerAtLogon'
        ValueType              = 'Dword'
        ValueData              = 0x1
    }
}

Configuration PackageManagementConfiguration {
    param (
        [PSCredential]$Credential,
        [string]$InstallationSharePath,
        [PSCredential]$InstallationShareCredential
    )

    Import-DscResource -ModuleName 'PackageManagement' -ModuleVersion '1.1.4.0'

    if ($InstallationSharePath -and $InstallationShareCredential) {
        PackageManagementSource PowerShellSource {
            Name                 = 'up-powershell'
            Ensure               = 'Present'
            SourceLocation       = Join-Path -Path $InstallationSharePath -ChildPath 'Modules'
            SourceCredential     = $InstallationShareCredential
            ProviderName         = 'PowerShellGet'
            InstallationPolicy   = 'Trusted'
            PsDscRunAsCredential = $Credential
        }

	    PackageManagement ChocolateyOneGetProvider { 
            Name                 = 'ChocoOneGet'
            RequiredVersion      = '0.1.0'
            Ensure               = 'Present'
            Source               = 'up-powershell'
            ProviderName         = 'PowerShellGet'
            PsDscRunAsCredential = $Credential
            DependsOn            = '[PackageManagementSource]PowerShellSource'
        }

        PackageManagementSource ChocolateySource {
            Name                 = 'up-chocolatey'
            Ensure               = 'Present'
            SourceLocation       = Join-Path -Path $InstallationSharePath -ChildPath 'Packages'
            SourceCredential     = $InstallationShareCredential
            ProviderName         = 'Choco'
            InstallationPolicy   = 'Trusted'
            PsDscRunAsCredential = $Credential
            DependsOn            = '[PackageManagement]ChocolateyOneGetProvider'
        }
    }
}

Configuration DhcpServer {
    param (
        $Properties,
        [bool]$Domain
    )

    Import-DscResource –ModuleName 'PSDesiredStateConfiguration'
    Import-DscResource –ModuleName 'xDhcpServer' -ModuleVersion '1.5.0.0'
    Import-DscResource –ModuleName 'bDhcpServer' -ModuleVersion '0.2.0.0'

    WindowsFeature DhcpFeature {
        Name               = 'DHCP'
    }
    bDhcpServerConfigurationCompletion DhcpCompletion {
        Ensure             = 'Present'
        DependsOn          = '[WindowsFeature]DhcpFeature'
    }
    WindowsFeature DhcpMgmtToolsFeature {
        Name               = 'RSAT-DHCP'
        DependsOn          = '[bDhcpServerConfigurationCompletion]DhcpCompletion'
    }

    if ($Domain) {
        xDhcpServerAuthorization DhcpServerAuthorization {
            Ensure             = 'Present'
            DependsOn          = '[bDhcpServerConfigurationCompletion]DhcpCompletion'
        }
    }

    # NOTE: Binding not needed (?), binds to correct interface automatically
    #       Set-DhcpServerv4Binding -InterfaceAlias 'Internal' -BindingState $true

    xDhcpServerScope DhcpScope {
        Ensure             = 'Present'
        Name               = $Properties.ScopeName
        AddressFamily      = $Properties.AddressFamily
        IPStartRange       = $Properties.StartRange
        IPEndRange         = $Properties.EndRange
        SubnetMask         = $Properties.SubnetMask
        LeaseDuration      = $Properties.LeaseDuration
        State              = 'Active'
        DependsOn          = '[bDhcpServerConfigurationCompletion]DhcpCompletion'
    }
    xDhcpServerOption DhcpOptions {
        Ensure             = 'Present'
        AddressFamily      = $Properties.AddressFamily
        ScopeID            = $Properties.ScopeId
        DnsServerIPAddress = $Properties.DnsServerIPAddress
        Router             = $Properties.DefaultGateway
        DependsOn          = '[xDhcpServerScope]DhcpScope'
    }

    $reservations = @()
    $allMachines = $Node.Environment.Nodes
    if (-not $allMachines) {
        $allMachines = $Node.Environment.Machines
    }
    foreach ($machine in $allMachines) {
        foreach ($networkAdapter in $machine.NetworkAdapters) {
            if ($networkAdapter.StaticMacAddress -and $networkAdapter.StaticIPAddress) {
                xDhcpServerReservation "DhcpReservation_$($machine.Name)_$($networkAdapter.Network.Name)" {
                    Ensure             = 'Present'
                    AddressFamily      = $Properties.AddressFamily
                    ScopeID            = $Properties.ScopeId
                    Name               = $machine.Name
                    ClientMACAddress   = $networkAdapter.StaticMacAddress
                    IPAddress          = $networkAdapter.StaticIPAddress
                    DependsOn          = '[xDhcpServerScope]DhcpScope'
                }
                $reservations += $networkAdapter.StaticMacAddress
            }
        }
    }

    if ($Properties.Reservations) {
        foreach ($reservation in $Properties.Reservations) {
            if ($reservation.Name -and $reservation.MacAddress -and $reservation.IPAddress -and $reservations -notcontains $reservation.MacAddress) {
                xDhcpServerReservation "DhcpReservation_$($reservation.Name)" {
                    Ensure             = 'Present'
                    AddressFamily      = $Properties.AddressFamily
                    ScopeID            = $Properties.ScopeId
                    Name               = $reservation.Name
                    ClientMACAddress   = $reservation.MacAddress
                    IPAddress          = $reservation.IPAddress
                    DependsOn          = '[xDhcpServerScope]DhcpScope'
                }
                $reservations += $reservation.MacAddress
            }
        }
    }
}

Configuration WdsServer {
    param (
        $Properties
    )

    Import-DscResource -ModuleName 'PSDesiredStateConfiguration'

    WindowsFeature WdsFeature {
        Name               = 'WDS'
    }

    File WdsRemoteInstall {
        Ensure             = 'Present'
        DestinationPath    = $Properties.Path
        Type               = 'Directory'
    }
}

Configuration DscPullServer {
    param (
        $Properties,
        [string]$InstallationSharePath,
        [PSCredential]$InstallationShareCredential
    )

    Import-DscResource -ModuleName 'PSDesiredStateConfiguration'
    Import-DscResource -ModuleName 'xPSDesiredStateConfiguration' -ModuleVersion '6.4.0.0'
    Import-DscResource -ModuleName 'xNetworking' -ModuleVersion '5.0.0.0'

    WindowsFeature DSCServiceFeature {
        Name                     = 'DSC-Service'
        Ensure                   = 'Present'
    }

    $dscServicePath = Join-Path -Path $env:ProgramFiles -ChildPath '\WindowsPowerShell\DscService'
    File RegistrationKeyFile {
        DestinationPath          = (Join-Path -Path $dscServicePath -ChildPath 'RegistrationKeys.txt')
        Type                     = 'File'
        Contents                 = $Properties.RegistrationKey
        Ensure                   = 'Present'
    }
    xDscWebService DSCPullServer {
        EndpointName             = 'PSDSCPullServer'
        Port                     = 8080
        CertificateThumbPrint    = 'AllowUnencryptedTraffic'
        Ensure                   = 'Present'
        PhysicalPath             = "$($env:SystemDrive)\inetpub\PSDSCPullServer"
        ModulePath               = (Join-Path -Path $dscServicePath -ChildPath 'Modules')
        ConfigurationPath        = (Join-Path -Path $dscServicePath -ChildPath 'Configuration')
        RegistrationKeyPath      = $dscServicePath
        State                    = 'Started'
        UseSecurityBestPractices = $false
        DependsOn                = '[WindowsFeature]DSCServiceFeature'
    }

    $tcpServiceVersion = '0.2.0'
    $tcpServiceInstallationPath = Join-Path -Path 'C:\Program Files\PSTCPService' -ChildPath $tcpServiceVersion
    $tcpServiceFilePath = Join-Path -Path $tcpServiceInstallationPath -ChildPath 'PSTCPService.exe'
    File InstallPSTCPService {
        Ensure             = 'Present'
        DestinationPath    = $tcpServiceInstallationPath
        Type               = 'Directory'
        Recurse            = $true
        SourcePath         = Join-Path -Path $InstallationSharePath -ChildPath "PSTCPService\$tcpServiceVersion"
        Credential         = $InstallationShareCredential
    }
    $dscDiscoveryServiceVersion = '1.0.0'
    $dscDiscoveryServiceFilePath = "C:\ProgramData\DscDiscoveryService\$dscDiscoveryServiceVersion\DscDiscoveryService.ps1"
    File InstallDscDiscoveryServiceScript {
        Ensure             = 'Present'
        DestinationPath    = $dscDiscoveryServiceFilePath
        Type               = 'File'
        MatchSource        = $true
        SourcePath         = Join-Path -Path $InstallationSharePath -ChildPath "DscDiscoveryService\$dscDiscoveryServiceVersion\DscDiscoveryService.ps1"
        Credential         = $InstallationShareCredential
    }
    # TODO: uninstall service if newer version is available; but how to determine...
    Service DscDiscoveryService {
        Name               = 'DscDiscoveryService'
        StartupType        = 'Automatic'
        State              = 'Running'
        Path               = """$tcpServiceFilePath"" -p 7000 --script ""$dscDiscoveryServiceFilePath"""
        DependsOn          = '[File]InstallPSTCPService','[File]InstallDscDiscoveryServiceScript'
    }

	xFirewall DiscoveryServiceFirewall {
        Ensure                   = 'Present'
        Name                     = 'Discovery Service'
        Direction                = 'InBound'
        LocalPort                = $Properties.DiscoveryPort
        Protocol                 = 'TCP'
        Profile                  = 'Any'
        Action                   = 'Allow'
        Enabled                  = 'True'
	}
}

Configuration InstallationShare {
    param (
        $Properties
    )

    Import-DscResource -ModuleName 'xSmbShare' -ModuleVersion '2.0.0.0'

    xSmbShare InstallationShare {
        Name                     = 'InstallationShare'
        Ensure                   = 'Present'
        Path                     = $Properties.Path
        ReadAccess               = $Properties.ReadAccess
        FullAccess               = $Properties.FullAccess
    }
}

Configuration BasicServer {
    Import-DscResource -ModuleName 'xComputerManagement' -ModuleVersion '2.0.0.0'

    xComputer ComputerName {
        Name                   = $Node.Name
    }
}

Configuration DomainController {
    param (
        $Properties,
        $Domain,
        [PSCredential]$DomainCredential
    )

    Import-DscResource –ModuleName 'PSDesiredStateConfiguration'
    Import-DscResource -ModuleName 'xComputerManagement' -ModuleVersion '2.0.0.0'
    Import-DscResource -ModuleName 'xActiveDirectory' -ModuleVersion '2.16.0.0'
    Import-DscResource -ModuleName 'xDnsServer' -ModuleVersion '1.7.0.0'

    xComputer ComputerName {
        Name                           = $Node.Name
    }

    WindowsFeature ADDSFeature {
        Name                           = 'AD-Domain-Services'
        DependsOn                      = '[xComputer]ComputerName'
    }
    WindowsFeature ADDSMgmtToolsFeature {
        Name                           = 'RSAT-ADDS-Tools'
        DependsOn                      = '[WindowsFeature]ADDSFeature'
    }

    xADDomain ADDSForest { 
        DomainName                     = $Domain.Name
        DomainAdministratorCredential  = $DomainCredential
        SafemodeAdministratorPassword  = $DomainCredential
        DependsOn                      = "[WindowsFeature]ADDSMgmtToolsFeature"
    }

    # TODO: store user-password as secure string (optional)
    # TODO: add group-memberships
    if ($Properties.Users) {
        foreach ($user in $Properties.Users) {
            $userCredential = New-Object -TypeName PSCredential -ArgumentList $user.UserName,(ConvertTo-SecureString -String $($user.Password) -AsPlainText -Force)
            xADUser "ADUser_$($user.UserName)" {
                UserName               = $user.UserName
                DomainName             = $Domain.Name
                Password               = $userCredential
                Ensure                 = 'Present'
                Enabled                = $true
                PasswordNeverExpires   = $user.PasswordNeverExpires
                DependsOn              = "[xADDomain]ADDSForest"
            }
        }
    }

    if ($Properties.DnsRecords) {
        foreach ($dnsRecord in $Properties.DnsRecords) {
            xDnsRecord "DnsRecord_$($dnsRecord.Name)" {
                Name                   = $dnsRecord.Name
                Target                 = $dnsRecord.Target
                Zone                   = $Domain.Name
	            Type                   = $dnsRecord.Type
                Ensure                 = 'Present'
                DependsOn              = "[xADDomain]ADDSForest"
            }
        }
    }
}

Configuration MemberServer {
    param (
        $Domain,
        [PSCredential]$DomainCredential
    )

    Import-DscResource –ModuleName 'PSDesiredStateConfiguration'
    Import-DscResource -ModuleName 'xActiveDirectory' -ModuleVersion '2.16.0.0'
    Import-DscResource -ModuleName 'xComputerManagement' -ModuleVersion '2.0.0.0'

    xWaitForADDomain WaitForDomain
    {
        DomainName             = $Domain.Name
        DomainUserCredential   = $DomainCredential
        RetryIntervalSec       = 30
        RetryCount             = 480
    }
    xComputer ComputerNameAndDomain {
        Name                   = $Node.Name
        DomainName             = $Domain.Name
        Credential             = $DomainCredential
        DependsOn              = '[xWaitForADDomain]WaitForDomain'
    }
}

Configuration ManagementServer {
    param (
        [PSCredential]$Credential,
        [string]$InstallationSharePath,
        [PSCredential]$InstallationShareCredential
    )

    Import-DscResource –ModuleName 'PSDesiredStateConfiguration'
    Import-DscResource -ModuleName 'PackageManagement' -ModuleVersion '1.1.4.0'

    WindowsFeature ADDSMgmtToolsFeature {
        Name                   = 'RSAT-ADDS-Tools'
    }
    WindowsFeature DnsMgmtToolsFeature {
        Name                   = 'RSAT-DNS-Server'
    }
    WindowsFeature DhcpMgmtToolsFeature {
        Name                   = 'RSAT-DHCP'
    }

    WindowsFeature WebMgmtToolsFeature {
        Name                   = 'Web-Mgmt-Tools'
    }

    WindowsFeature WdsMgmtToolsFeature {
        Name                   = 'WDS'
    }

    <#Package SqlServer2016ManagementStudio {
        Name        = 'SQL Server 2016 Management Studio'
        Ensure      = 'Present'
        ProductId   = 'CD29C330-B9F9-4422-B277-925D943D6C81'
        Arguments   = '/install /quiet /norestart'
        LogPath     = 'C:\_provisioning\logs\SSMS-Setup-ENU.txt'
        Path        = Join-Path -Path $InstallationSharePath -ChildPath 'SSMS-Setup-ENU-17.1.exe'
        Credential  = $InstallationShareCredential
    }#>

	<#PackageManagement ServiceFabricSDKPackage { 
        Name                 = 'ServiceFabric.SDK'
        RequiredVersion      = '2.7.198'
        Ensure               = 'Present'
        Source               = 'up-chocolatey'
        PsDscRunAsCredential = $Credential
    }#>

    Archive ServiceFabricScripts {
        Path                   = Join-Path -Path $InstallationSharePath -ChildPath 'ServiceFabric\Microsoft.Azure.ServiceFabric.WindowsServer.5.7.198.9494.zip'
        Destination            = 'C:\ServiceFabric'
        Credential             = $InstallationShareCredential
    }
    $fileName = 'MicrosoftAzureServiceFabric.5.7.198.9494.cab'
    File ServiceFabricDeploymentRuntimePackages {
        Ensure             = 'Present'
        DestinationPath    = Join-Path -Path 'C:\ServiceFabric\DeploymentRuntimePackages' -ChildPath $fileName
        Type               = 'File'
        SourcePath         = Join-Path -Path $InstallationSharePath -ChildPath (Join-Path -Path 'ServiceFabric' -ChildPath $fileName)
        Credential         = $InstallationShareCredential
		DependsOn          = '[Archive]ServiceFabricScripts'
    }

	<#PackageManagement NotepadPlusPlus {
		Name               = 'notepadplusplus'
		Ensure             = 'Present'
		Source             = 'up-chocolatey'
		DependsOn          = '[PackageManagementSource]ChocolateySource'
	}#>
}

Configuration SqlServer2016 {
    param (
        $Properties,
        [PSCredential]$DomainCredential,
        [string]$InstallationSharePath,
        [PSCredential]$InstallationShareCredential
    )

    Import-DscResource –ModuleName 'PSDesiredStateConfiguration'
    Import-DscResource -ModuleName 'xSqlServer' -ModuleVersion '8.0.0.0'
    Import-DscResource -ModuleName 'xNetworking' -ModuleVersion '5.0.0.0'

    if (-not $Properties.InstanceName) {
        $Properties.InstanceName = 'MSSQLSERVER'
    }
    if (-not $Properties.Features) {
        $Properties.Features = @('SQLENGINE')
    }
    if (-not $Properties.DataFolderPath) {
        $Properties.DataFolderPath = 'C:\Data'
    }
    if ($Properties.SAPassword) {
        $SAPassword = New-Object -TypeName PSCredential -ArgumentList 'sa',(ConvertTo-SecureString -String $($Properties.SAPassword) -AsPlainText -Force)
    }
    else {
        $SAPassword = New-Object -TypeName PSCredential -ArgumentList 'sa',(ConvertTo-SecureString -String $($Node.AdministratorPassword) -AsPlainText -Force)
    }

    $sqlInstallationSharePath = Join-Path -Path $InstallationSharePath -ChildPath 'sql2016_dev'

    <#$HotfixKB3138367LogFilePath = 'C:\_provisioning\Log_KB3138367.txt'
    Package HotfixKB3138367 {
        Name                   = 'Microsoft Visual C++ 2013 Redistributable (x64) - 12.0.40649'
        Ensure                 = 'Present'
        ProductId              = '5d0723d3-cff7-4e07-8d0b-ada737deb5e6'
        Arguments              = "/install /quiet /norestart /log HotfixKB3138367LogFilePath"
        LogPath                = $HotfixKB3138367LogFilePath
        Path                   = Join-Path -Path $InstallationSharePath -ChildPath 'vcredist_x64.exe'
        Credential             = $DomainCredential
    }

    File NETFrameworkCoreFiles {
        DestinationPath        = 'C:\_provisioning\w2016_sxs'
        Type                   = 'Directory'
        Ensure                 = 'Present'
        SourcePath             = Join-Path -Path $InstallationSharePath -ChildPath 'w2016\sources\sxs'
        Credential             = $DomainCredential
        Recurse                = $true
        DependsOn              = '[Package]HotfixKB3138367'
    }

    WindowsFeature NETFrameworkCore {
        Name                   = 'NET-Framework-Core'
        Ensure                 = 'Present'
        Source                 = 'C:\_provisioning\w2016_sxs'
        DependsOn              = '[File]NETFrameworkCoreFiles'
    }#>

    xSqlServerSetup SqlServer2016 {
        SourcePath             = $sqlInstallationSharePath
        SourceCredential       = $InstallationShareCredential

        ProductKey             = $Node.AllProperties.SqlProductKey
        Features               = [string]::Join(',', $Properties.Features)

        # SQLENGINE
        InstanceName           = $Properties.InstanceName
        SecurityMode           = 'SQL'
        SAPwd                  = $SAPassword
        InstallSQLDataDir      = $Properties.DataFolderPath
        SQLCollation           = 'Latin1_General_CI_AS'
        SQLSysAdminAccounts    = ($DomainCredential).UserName
        #SQLSvcAccount          = $Node.ServiceAccount
        #AgtSvcAccount          = $Node.ServiceAccount

        # FULLTEXT
        #FTSvcAccount           = "NT Service\MSSQLFDLauncher"

        # AS
        #ASSvcAccountUserName   = "NT AUTHORITY\SYSTEM"      # "NT Service\MSSQLServerOLAPService"
        ASDataDir              = Join-Path -Path $Properties.DataFolderPath -ChildPath 'OLAP'
        ASSysAdminAccounts     = ($DomainCredential).UserName

        #DependsOn              = '[WindowsFeature]NETFrameworkCore'
    }

    xSQLServerNetwork SqlServer2016TcpIp {
        InstanceName           = $Properties.InstanceName
        ProtocolName           = 'tcp'
        IsEnabled              = $true
        TCPPort                = 1433
        RestartService          = $true 
        DependsOn              = '[xSqlServerSetup]SqlServer2016'
    }
    
    <#xSqlServerFirewall SqlServer2016Firewall {
        SourcePath             = $sqlInstallationSharePath
        SourceCredential       = $DomainCredential
        Features               = [string]::Join(',', $Properties.Features)
        InstanceName           = $Properties.InstanceName
        DependsOn              = '[xSQLServerNetwork]SqlServer2016TcpIp'
    }#>
	xFirewall SqlServer2016Firewall {
        Ensure             = 'Present'
        Name               = 'SQL Server:1433'
        Direction          = 'InBound'
        LocalPort          = '1433'
        Protocol           = 'TCP'
        Profile            = 'Any'
        Action             = 'Allow'
        Enabled            = 'True'
	}
}

Configuration TfsServer2017 {
    param (
        $Properties,
        [PSCredential]$DomainCredential,
        [string]$InstallationSharePath,
        [PSCredential]$InstallationShareCredential
    )

    Import-DscResource –ModuleName 'PSDesiredStateConfiguration'
    Import-DscResource -ModuleName 'xNetworking' -ModuleVersion '5.0.0.0'
    Import-DscResource –ModuleName 'xWebAdministration' -ModuleVersion '1.18.0.0'
    Import-DscResource -ModuleName 'bTfsServer' -ModuleVersion '0.4.6.0'

    SqlServer2016 SqlServer2016 {
        DomainCredential = $DomainCredential
        InstallationSharePath = $InstallationSharePath
		InstallationShareCredential = $InstallationShareCredential
        Properties = @{
            Features = @('SQLENGINE','FULLTEXT','RS','AS')
            InstanceName = 'MSSQLSERVER'
        }
    }

    # stop the default website, so port 80 is available
    WindowsFeature WebServer {
        Name               = "Web-Server"
        Ensure             = "Present"
    }
    xWebsite DefaultSite {
        Ensure             = "Present"
        Name               = "Default Web Site"
        State              = "Stopped"
        PhysicalPath       = "C:\inetpub\wwwroot"
        DependsOn          = "[WindowsFeature]WebServer"
    }

    if (-not $Properties.TfsServiceAccountUserName) {
        $Properties.TfsServiceAccountUserName = 'NT AUTHORITY\\Network Service'
    }
    if ($Properties.TfsServiceAccountPassword) {
        $tfsServiceAccount = New-Object -TypeName PSCredential -ArgumentList $Properties.TfsServiceAccountUserName,(ConvertTo-SecureString -String $($Properties.TfsServiceAccountPassword) -AsPlainText -Force)
    }

    if ($Properties.ReportReaderAccountUserName -and $Properties.ReportReaderAccountPassword) {
        $reportReaderAccount = New-Object -TypeName PSCredential -ArgumentList $Properties.ReportReaderAccountUserName,(ConvertTo-SecureString -String $($Properties.ReportReaderAccountPassword) -AsPlainText -Force)
    }

    # TODO: use sa-tfs as service-account
    # NOTE: installing a TFS Server 2013 with a domain-service-account through DSC resulted in a crashing AppPool
    bTfsServerSetup TfsServer2017 {
        SourcePath                  = Join-Path -Path $InstallationSharePath -ChildPath 'tfs2017.1'
        SourceCredential            = $InstallationShareCredential
        Name                        = $Node.NodeName
        Ensure                      = 'Present'
        WebSitePort                 = 80
        WebSiteVirtualDirectoryName = ''
        LogPath                     = "C:\_provisioning\logs"
        SendFeedback                = $false
        SqlServerInstance           = $Node.NodeName
        TeamProjectCollectionName   = 'DefaultCollection'
        TfsServiceAccountUserName   = $Properties.TfsServiceAccountUserName
        TfsServiceAccount           = $tfsServiceAccount
        ReportReaderAccount         = $reportReaderAccount
        TfsAdminCredential          = $DomainCredential
        FileCacheDirectory          = 'D:\Cache'
        DependsOn                   = '[SqlServer2016]SqlServer2016'
    }

	xFirewall TfsServerFirewall {
        Ensure             = 'Present'
        Name               = 'Team Foundation Server:80'
        Direction          = 'InBound'
        LocalPort          = '80'
        Protocol           = 'TCP'
        Profile            = 'Any'
        Action             = 'Allow'
        Enabled            = 'True'
	}
}

Configuration Tfs2017Agent {
    param (
        [string]$InstallationSharePath,
        [PSCredential]$InstallationShareCredential
    )

    Import-DscResource –ModuleName 'PSDesiredStateConfiguration'
    Import-DscResource -ModuleName 'PackageManagement' -ModuleVersion '1.1.4.0'

    Archive InstallTfs2017Agent {
        Path                   = Join-Path -Path $InstallationSharePath -ChildPath 'tfs-extensions\vsts-agent-win7-x64-2.112.0.zip'
        Destination            = 'C:\agent'
        Credential             = $InstallationShareCredential
    }

	PackageManagement ServiceFabricSDKPackage { 
        Name                 = 'ServiceFabric.SDK'
        RequiredVersion      = '2.7.198'
        Ensure               = 'Present'
        Source               = 'up-chocolatey'
        PsDscRunAsCredential = $Credential
    }
}

Configuration ContainerHost {
    param (
        $Properties,
        [PSCredential]$Credential,
        [string]$InstallationSharePath,
        [PSCredential]$InstallationShareCredential
    )

    Import-DscResource -ModuleName 'PSDesiredStateConfiguration'
    Import-DscResource -ModuleName 'PackageManagement' -ModuleVersion '1.1.4.0'

    WindowsFeature ContainersFeature {
        Name               = 'Containers'
    }

    #PackageParameters = "--insecure-registries='http://10.42.32.5:5000,http://10.42.32.160:5000' --group='Network Service'"
    $packageParameters = ""
    if ($Properties.InsecureRegistry) {
        $packageParameters += " --insecure-registries='$($Properties.InsecureRegistry)'"
    }
    if ($Properties.Group) {
        $packageParameters += " --group='$($Properties.Group)'"
    }

	PackageManagement DockerPackage { 
        Name                 = 'docker.embedded'
        RequiredVersion      = '17.06.1.0'
        Ensure               = 'Present'
        Source               = 'up-chocolatey'
        ProviderName         = 'Choco'
        AdditionalParameters = @{
                                    Switches = 'Prerelease Force'
                                    PackageParameters = """$packageParameters"""
                                }
        PsDscRunAsCredential = $Credential
        DependsOn = '[WindowsFeature]ContainersFeature'
    }

	PackageManagement DockerModule { 
        Name                 = 'docker'
        RequiredVersion      = '0.1.0.111'
        Ensure               = 'Present'
        Source               = 'up-powershell'
        PsDscRunAsCredential = $Credential
    }
}

Configuration ContainerRegistry {
    param (
        [PSCredential]$Credential,
        [string]$InstallationSharePath,
        [PSCredential]$InstallationShareCredential
    )

    Import-DscResource -ModuleName 'PSDesiredStateConfiguration'
    Import-DscResource -ModuleName 'xNetworking' -ModuleVersion '5.0.0.0'

    ContainerHost ContainerHost {
		Credential = $Credential
        InstallationSharePath = $InstallationSharePath
        InstallationShareCredential = $InstallationShareCredential
    }

	xFirewall RegistryFirewall {
        Ensure             = 'Present'
        Name               = 'Registry:5000'
        Direction          = 'InBound'
        LocalPort          = '5000'
        Protocol           = 'TCP'
        Profile            = 'Any'
        Action             = 'Allow'
        Enabled            = 'True'
	}

    $imageFilePath = Join-Path -Path $InstallationSharePath -ChildPath 'docker_images\sixeyed_registry.tar'
    $imageName = 'sixeyed/registry:latest'
    $registryVolumePath = 'C:\Volumes\Registry'
    Script RegistryContainerImage {
        TestScript = {
            return !!(Get-ContainerImage -ImageIdOrName $using:imageName)
        }
        SetScript = {
            Import-ContainerImage -FilePath $using:imageFilePath
        }
        GetScript = {
            $image = Get-ContainerImage -ImageIdOrName $using:imageName
            return @{
                ID = $image.ID
                RepoTags = $image.RepoTags
            }
        }
        PsDscRunAsCredential = $InstallationShareCredential
        DependsOn = '[ContainerHost]ContainerHost'
    }
    File RegistryVolumeDirectory {
        Ensure             = 'Present'
        DestinationPath    = $registryVolumePath
        Type               = 'Directory'
    }
    Script RegistryContainer {
        TestScript = {
            return !!(Get-Container | Where-Object { $_.Image -eq $using:imageName })
        }
        SetScript = {
            $argumentList = @('run', '-d', '-p', '5000:5000', '-v', "$($using:registryVolumePath):c:\data", '--restart', 'unless-stopped', $using:imageName)
            Start-Process -FilePath 'C:\Windows\system32\docker.exe' -ArgumentList $argumentList -Wait
        }
        GetScript = {
            return @{
            }
        }
        DependsOn = '[File]RegistryVolumeDirectory', '[Script]RegistryContainerImage'
    }
}

Configuration ServiceFabricNode {
    Import-DscResource -ModuleName 'PSDesiredStateConfiguration'
    Import-DscResource -ModuleName 'xNetworking' -ModuleVersion '5.0.0.0'

    Service RemoteRegistryService {
        Name               = 'RemoteRegistry'
        StartupType        = 'Automatic'
        State              = 'Running'
    }

	xFirewall RemoteRegistryFirewall {
        Ensure             = 'Present'
        Name               = 'RemoteRegistry:445'
        Direction          = 'InBound'
        LocalPort          = '445'
        Protocol           = 'TCP'
        Profile            = 'Any'
        Action             = 'Allow'
        Enabled            = 'True'
	}
    # New-NetFirewallRule -DisplayName 'ServiceFabricReverseProxy' -LocalPort 19008 -Direction Inbound -Protocol TCP -Profile Any
}

Configuration LabEnvironment {
    Import-DscResource –ModuleName 'PSDesiredStateConfiguration'

    Node $AllNodes.NodeName {

        <# The following initialization is done in the setup-complete script
            + Initialize PowerShell environment (ExecutionPolicy:Unrestricted)
            + Enable PS-Remoting
            + Enable CredSSP
            + Format Extra-Disk (only if present and not yet formatted)
            + Change LCM:RebootNodeIfNeeded
            + Apply this configuration
        #>

        $InstallationShareNode = $AllNodes | Where-Object { $_.Roles | Where-Object { $_.Name -eq 'InstallationShare' } }
        if ($InstallationShareNode) {
            $InstallationShareRole = $InstallationShareNode.Roles | Where-Object { $_.Name -eq 'InstallationShare' }
            if ($InstallationShareNode -and $InstallationShareRole) {
                $InstallationSharePath = "\\$($InstallationShareNode.Name)\InstallationShare"
            }
        }
        else {
            $InstallationSharePath = $Node.AllProperties.InstallationSharePath
        }

        if (-not $InstallationSharePath) {
            throw "no installation-share path"
        }

        if ($Node.AdministratorPassword -is [string]) {
            $machineCredential = New-Object -TypeName PSCredential -ArgumentList "$($Node.Name)\Administrator",(ConvertTo-SecureString -String $Node.AdministratorPassword -AsPlainText -Force)
        }
        else {
            $machineCredential = New-Object -TypeName PSCredential -ArgumentList "$($Node.Name)\Administrator",$Node.AdministratorPassword
        }

        if ($Node.Domain) {
            $administratorUserName = "$($Node.Domain.Name)\Administrator"
            $administratorPassword = $Node.Domain.AdministratorPassword

            if ($administratorPassword -is [string]) {
                $credential = New-Object -TypeName PSCredential -ArgumentList $administratorUserName,(ConvertTo-SecureString -String $administratorPassword -AsPlainText -Force)
            }
            else {
                $credential = New-Object -TypeName PSCredential -ArgumentList $administratorUserName,$administratorPassword
            }
        }
        else {
            $credential = $machineCredential
        }

        CommonServer CommonServer {
            AdministratorPassword = $machineCredential
            IsServiceFabricNode = !!($Node.Roles | Where-Object { $_.Name -eq 'ServiceFabricNode' })
        }
        $dependsOn = @('[CommonServer]CommonServer')

        if ($Node.Domain) {
            $roleDomainController = $Node.Roles | Where-Object { $_.Name -eq 'DomainController' }
            if ($roleDomainController) {
                DomainController DomainController {
                    Domain = $Node.Domain
                    DomainCredential = $credential
                    Properties = $roleDomainController
                    DependsOn = $dependsOn
                }

                $dependsOn = @('[DomainController]DomainController')
            }
            else {
                MemberServer MemberServer {
                    Domain = $Node.Domain
                    DomainCredential = $credential
                    DependsOn = $dependsOn
                }

                $dependsOn = @('[MemberServer]MemberServer')
            }

            PackageManagementConfiguration PackageManagementConfiguration {
                Credential = $credential
                InstallationSharePath = $InstallationSharePath
                InstallationShareCredential = $credential
                DependsOn = $dependsOn
            }
            $dependsOn = @('[PackageManagementConfiguration]PackageManagementConfiguration')
        }
        else {
            BasicServer BasicServer {
                DependsOn = $dependsOn
            }
            $dependsOn = @('[BasicServer]BasicServer')
        }

        foreach ($role in $Node.Roles) {
            switch ($role.Name) {
                'DhcpServer' {
                    DhcpServer DhcpServer {
                        Properties = $role
                        Domain = $false
                        DependsOn = $dependsOn
                    }
                    $dependsOn = '[DhcpServer]DhcpServer'
                }
                'WdsServer' {
                    WdsServer WdsServer {
                        Properties = $role
                        DependsOn = $dependsOn
                    }
                    $dependsOn = '[WdsServer]WdsServer'
                }
                'DscPullServer' {
                    DscPullServer DscPullServer {
                        Properties = $role
						InstallationSharePath = $InstallationSharePath
						InstallationShareCredential = $credential
                        DependsOn = $dependsOn
                    }
                    $dependsOn = '[DscPullServer]DscPullServer'
                }
                'InstallationShare' {
                    InstallationShare InstallationShare {
                        Properties = $role
                        DependsOn = $dependsOn
                    }
                    $dependsOn = '[InstallationShare]InstallationShare'
                }
                'ManagementServer' {
                    ManagementServer ManagementServer {
                        Credential = $credential
                        InstallationSharePath = $InstallationSharePath
                        InstallationShareCredential = $credential
                        DependsOn = $dependsOn
                    }
                    $dependsOn = '[ManagementServer]ManagementServer'
                }
                { $_ -match '^SqlServer' } {
                    SqlServer2016 SqlServer2016 {
                        Properties = $role
                        DomainCredential = $credential
                        InstallationSharePath = $InstallationSharePath
                        InstallationShareCredential = $credential
                        DependsOn = $dependsOn
                    }
                    $dependsOn = '[SqlServer2016]SqlServer2016'
                }
                'TfsServer' {
                    TfsServer2017 TfsServer2017 {
                        Properties = $role
                        DomainCredential = $credential
                        InstallationSharePath = $InstallationSharePath
                        InstallationShareCredential = $credential
                        DependsOn = $dependsOn
                    }
                    $dependsOn = '[TfsServer2017]TfsServer2017'
                }
                'TfsAgent' {
                    Tfs2017Agent Tfs2017Agent {
                        InstallationSharePath = $InstallationSharePath
                        InstallationShareCredential = $credential
                        DependsOn = $dependsOn
                    }
                    $dependsOn = '[Tfs2017Agent]Tfs2017Agent'
                }
                { $_ -match '^ContainerHost' } {
                    ContainerHost ContainerHost {
                        Properties = $role
                        Credential = $credential
                        InstallationSharePath = $InstallationSharePath
                        InstallationShareCredential = $credential
                        DependsOn = $dependsOn
                    }
                    $dependsOn = '[ContainerHost]ContainerHost'
                }
                'ContainerRegistry' {
                    ContainerRegistry ContainerRegistry {
                        Credential = $credential
                        InstallationSharePath = $InstallationSharePath
                        InstallationShareCredential = $credential
                        DependsOn = $dependsOn
                    }
                    $dependsOn = '[ContainerRegistry]ContainerRegistry'
                }
                'ServiceFabricNode' {
                    ServiceFabricNode ServiceFabricNode {
                        DependsOn = $dependsOn
                    }
                    $dependsOn = '[ServiceFabricNode]ServiceFabricNode'
                }
            }
        }
    }
}
