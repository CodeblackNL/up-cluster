<#
.SYNOPSIS
    Returns node-specific information for DSC client configuration.
.DESCRIPTION
    Returns node-specific information for DSC client configuration.
    This consists of the url & registration-key for the DSC pull server and the configuration-name for the node.
    The configuartion-name is determined by looking up the MACAddress in the cluster or environment configuration in one of the folloing known locations:
      $PSScriptRoot,
      C:\ProgramData\UPCluster\,
      C:\_provisioning\.

.NOTES
    Versions:
    - 1.0.0  12-08-2017  Initial version

.PARAMETER Path
    The path from the request.
.PARAMETER QueryString
    The query-string from the request.
.PARAMETER Query
    The query from the request.
.PARAMETER Method
    The method from the request.
.PARAMETER Body
    The body from the request.
.PARAMETER ContentType
    The content-type from the request.
.PARAMETER Headers
    The headers from the request.
#>
param (
    [string]$Path,
    [string]$QueryString,
    $Query,
    [string]$Method,
    [string]$Body,
    [string]$ContentType,
    $Headers
)

$logFilePath = Join-Path -Path 'C:\Windows\Temp' -ChildPath "DscDiscoveryService_$([DateTime]::UtcNow.ToString('yyyyMMdd_HHmmss'))_$([Guid]::NewGuid()).log"
#$logFilePath = Join-Path -Path $PSScriptRoot -ChildPath "logs\$([DateTime]::UtcNow.ToString('yyyyMMdd_HHmmss'))_$([Guid]::NewGuid()).log"
#New-Item -Path (Split-Path -Path $logFilePath -Parent) -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

Start-Transcript -Path $logFilePath | Out-Null

try {
    $receivedData = ConvertFrom-Json $Body

    $dscPullServerIPAddress = (Get-NetAdapter | Get-NetIPAddress -AddressFamily IPv4).IPAddress
    try {
        Import-Module WebAdministration
        if ((Get-Website -Name PSDSCPullServer | Get-WebBinding).bindingInformation -match '.*:(?<port>\d*):.*') {
            $dscPullServerPort = $Matches.port
        }
    }
    catch { }
    # NOTE: service-account does not have access to web-administration; make sure default is valid
    if (-not $dscPullServerPort) {
        $dscPullServerPort = 8080
    }
    $dscPullServerUrl = "http://$($dscPullServerIPAddress):$($dscPullServerPort)/PSDSCPullServer.svc"
    $dscPullServerRegistrationKey = "$(Get-Content -Path 'C:\Program Files\WindowsPowerShell\DscService\RegistrationKeys.txt')"

    $configurationFileNames = @(
        'environment.json'
        'cluster.json'
    )
    $configurationFolderPaths = @(
          $PSScriptRoot
          'C:\ProgramData\UPCluster\'
          'D:\Provisioning\'
          'C:\_provisioning\'
          'D:\Projects.GitHub\Labs.UP'
    )

    $configurationFilePath = $configurationFolderPaths `
        | Where-Object { $_ } `
        | ForEach-Object {
            $folderPath = $_
            $configurationFileNames `
                | ForEach-Object { Join-Path -Path $folderPath -ChildPath $_ }
          } `
        | Where-Object { Test-Path -Path $_ -PathType Leaf } `
        | Select-Object -First 1

    if ($configurationFilePath) {
        $configuration = Get-Content -Path $configurationFilePath | ConvertFrom-Json
        $nodes = $configuration.Nodes
        if (-not $nodes) {
            $nodes = $configuration.Machines
        }
        $configurationName = ($nodes `
            | Where-Object { @($_.NetworkAdapters.StaticMacAddress) | Where-Object { $_  -in @($receivedData.NetworkAdapters.MacAddress) } } `
            | Select-Object -First 1).Name
    }

    $responseData = @{
        TimeStamp = [DateTime]::Now
        DscPullServerUrl = $dscPullServerUrl
        DscPullServerRegistrationKey = $dscPullServerRegistrationKey
        DscConfigurationName = $configurationName
        ConfigurationFilePath = $configurationFilePath
    }

    return @{
        Body = ($responseData | ConvertTo-Json -Depth 9)
        StatusCode = 200
        ContentType = 'application/json'
    }
}
catch {
    $errorResponseData = @{
        Error = $_.Exception.Message
    }

    return @{
        Body = ($errorResponseData | ConvertTo-Json -Depth 9)
        StatusCode = 500
        ContentType = 'application/json'
    }
}
finally {
    Stop-Transcript | Out-Null
}
