#######################################
#region Initialize & load cluster-configuration
#######################################

Import-Module 'D:\Projects.GitHub\UPCluster\src\UPCluster.psd1' -Force
$scriptPath = $PSScriptRoot
Set-Location -Path $scriptPath

Import-UPClusterConfiguration -Path (Join-Path -Path $scriptPath -ChildPath 'up-05.json')

#endregion
#######################################
return

#######################################
#region Prepare installation disk
#######################################

$installationDriveLetter = 'F'
. (Join-Path -Path $scriptPath -ChildPath 'Scripts\Initialize-InstallationDisk.ps1') -Drive $installationDriveLetter

#endregion
#######################################

#######################################
#region Prepare share disk
#######################################

$shareDriveLetter = 'F'
. (Join-Path -Path $scriptPath -ChildPath 'Scripts\Initialize-ShareDisk.ps1') -Drive $shareDriveLetter -Force
Export-UPClusterConfiguration -OutputPath "$($shareDriveLetter):\Provisioning\cluster.json" -Force

#endregion
#######################################

#######################################
#region Configure DSC Pull Server
#######################################

# On DSC Pull Server:
#   D:\Provisioning\Initialize-DscPullServer.ps1
#   D:\Provisioning\Initialize-WdsServer.ps1

Copy-UPClusterConfiguration -Name 'UP-00' -Destination 'C:\ProgramData\UPCluster\cluster.json'

. (Join-Path -Path $scriptPath -ChildPath 'Provisioning\Update-DscResourceModules.ps1')
. (Join-Path -Path $scriptPath -ChildPath 'Provisioning\Install-DscResourceModules.ps1')

Update-UPCluster -Publish

Invoke-UPClusterNodeCommand -Name 'UP-00' -ScriptBlock {
    . D:\Provisioning\Initialize-DscPullClient.ps1 -DiscoveryServer 'UP-00'
}

#endregion
#######################################

#######################################
#region Publish & update DSC-configuration
#######################################
#. (Join-Path -Path $scriptPath -ChildPath 'Scripts\Save-DscResourceModules.ps1')
. (Join-Path -Path $scriptPath -ChildPath 'Scripts\Update-DscResourceModules.ps1')
. (Join-Path -Path $scriptPath -ChildPath 'Scripts\Install-DscResourceModules.ps1')

Update-UPCluster -Wait

#endregion
#######################################

#######################################
#region Clean Service Fabric installation
#######################################

$cluster = Get-UPClusterConfiguration
$nodes = $cluster.Nodes `
    |? { $_.Roles |? { $_.Name -match 'ServiceFabricNode' } } `
    |? { $_.Name -notin 'upvm-sf4','upvm-sf5' }

$nodes |% {
    Invoke-UPClusterNodeCommand -Node $_ -ScriptBlock {
        #$env:COMPUTERNAME
        #Get-CimInstance -ClassName 'Win32_LogicalDisk' |% { "$($env:COMPUTERNAME) $($_.DeviceID) $(($_.Size - $_.FreeSpace) / 1GB) (free: $($_.FreeSpace / 1GB))" }

        #Remove-Item -Path 'C:\SF\' -Recurse -Force -ErrorAction SilentlyContinue
        #Get-ChildItem -Path 'C:\ProgramData\SF' -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

        $scriptPath = 'C:\Program Files\Microsoft Service Fabric\bin\Fabric\Fabric.Code\CleanFabric.ps1'
        if (Test-Path -Path $scriptPath) {
            Write-Host "$($env:COMPUTERNAME) script found; executing..."
            . $scriptPath
        }
        else {
            Write-Host "$($env:COMPUTERNAME) script NOT found"
        }
    }
}

#######################################
#region Create VM's
#######################################
$environment = Get-LabEnvironment -Path (Join-Path -Path $scriptPath -ChildPath 'up-vm.json')
#$environment = Get-LabEnvironment UPVM
$environment | Get-LabMachine UPVM-DSC  | New-LabVM -Verbose -Start
$environment | Get-LabMachine UPVM-DC   | New-LabVM -Verbose -Start
$environment | Get-LabMachine UPVM-MGMT | New-LabVM -Verbose -Start
$environment | Get-LabMachine UPVM-TFS  | New-LabVM -Verbose -Start
$environment | Get-LabMachine UPVM-TFS1 | New-LabVM -Verbose -Start
$environment | Get-LabMachine UPVM-REG  | New-LabVM -Verbose -Start
$environment | Get-LabMachine UPVM-SF1,UPVM-SF2,UPVM-SF3,UPVM-SF4,UPVM-SF5 | New-LabVM -Verbose -Start

#endregion
#######################################

#######################################
#region Miscellaneous
#######################################
<#
Get-NetIPInterface
New-NetIPAddress –InterfaceIndex 12 –IPAddress 10.8.0.x –PrefixLength 24 #–DefaultGateway 10.8.0.n
Get-NetFirewallRule -Name *ERQ* | Enable-NetFirewallRule
#>
<#
Stop-Service Docker
dockerd --unregister-service
Remove-Item C:\Windows\System32\docker.exe
Remove-Item C:\Windows\System32\dockerd.exe
Update-DscConfiguration -wait -Verbose
#>
#endregion
#######################################


