param (
    [string]$DiscoveryServer
)

$setupFolder = $PSScriptRoot
$logFilePath = Join-Path -Path $setupFolder -ChildPath 'log.txt'

#######################################
#region Functions
#######################################

function Write-Log {
    param (
        [string]$Level,
        [string]$Message
    )

    $timestamp = [System.DateTime]::Now.TimeOfDay.ToString()

    # FATAL, ERROR, WARNING, INFO, DEBUG, TRACE
    if (!$Level) {
        $Level = "INFO"    
    }
    $formattedMessage = "$timestamp - $($Level.PadLeft(8)) - $Message"

    switch ($level) {
        "FATAL"   { Write-Host $formattedMessage -ForegroundColor White -BackgroundColor Red }
        "ERROR"   { Write-Host $formattedMessage -ForegroundColor White -BackgroundColor Red }
        "WARNING" { Write-Host $formattedMessage -ForegroundColor Yellow }
        "INFO"    { Write-Host $formattedMessage -ForegroundColor White }
        "DEBUG"   { Write-Host $formattedMessage -ForegroundColor Cyan }
        "TRACE"   { Write-Host $formattedMessage -ForegroundColor Gray }
        default   { Write-Host $formattedMessage -ForegroundColor White }
    }

    if ($logFilePath) {
        Add-Content -Path $logFilePath -Value $formattedMessage
    }
}

function Discover-DscPullServer {
    param (
        [string]$Server,
        [int]$Port = 7000,
        [int]$RetryCount = 12,
        [int]$RetryWaitTime = 5
    )

    if (-not $Server) {
        $Server = (Get-NetAdapter `
            | ForEach-Object { ((Get-ItemProperty -Path ('HKLM:\SYSTEM\CurrentControlSet\services\Tcpip\Parameters\Interfaces\{0}' -f $_.InterfaceGuid) -Name DhcpServer -ErrorAction SilentlyContinue).DhcpServer) } `
            | Where-Object { $_ -and [System.Net.IPAddress]::Parse($_) -ne [System.Net.IPAddress]::Broadcast } `
            | Select-Object -First 1)
    }

    $sendData = @{
        TimeStamp = [DateTime]::Now
        ComputerName = $env:COMPUTERNAME
        NetworkAdapters = Get-NetAdapter | ForEach-Object {
            @{
                Name = $_.Name
                MacAddress = $_.MacAddress
                IPAddresses = ($_ | Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
            }
        }
    }

    $uri = "http://$($Server):$($Port)/"
    Write-Log "INFO" "Connecting to '$uri'..."
    $response = $null
    $attempts = 0
    while (-not $response -and $attempts -lt $RetryCount) {
        $attempts++
        try {
            $response = Invoke-WebRequest -Uri $uri -UseBasicParsing -Method Post -Body ($sendData | ConvertTo-Json -Depth 9 )
            if ($response -and $response.StatusCode -eq 200) {
                Write-Log "INFO" "Connected"
            }
            else {
                Write-Log "WARNING" "Request failed ($($response.StatusCode)); retrying..."
                $response = $null
                Start-Sleep -Seconds $RetryWaitTime
            }
        }
        catch {
            Write-Log "ERROR" "$($_.Exception.Message)"
            Write-Log "WARNING" "Connection failed; retrying..."
            Start-Sleep -Seconds $RetryWaitTime
        }
    }

    if ($response) {
        Write-Log "DEBUG" "Received: $($response.Content)"
        return ConvertFrom-Json $response.Content
    }
}

#endregion
#######################################

try {
    Write-Log "INFO" "Starting setup-complete script '$($MyInvocation.InvocationName)'"
    Write-Log "INFO" "Running as '$($env:USERNAME)'"

    #######################################
    #region Delete unattend-file
    #######################################
    Write-Log "INFO" "Deleting unattend-file"
    $unattendFilePath = 'C:\unattend.xml'
    if (Test-Path -Path $unattendFilePath -PathType Leaf) {
        Remove-Item -Path $unattendFilePath -Force
        Write-Log "INFO" "Finished deleting unattend-file '$unattendFilePath'"
    }
    else {
        Write-Log "INFO" "Unattend-file '$unattendFilePath' not found"
    }
    #endregion
    #######################################

    #######################################
    #region Initialize PowerShell environment
    #######################################
    Write-Log "INFO" "Setting execution policy"
    Set-ExecutionPolicy Unrestricted -Scope CurrentUser -Force -ErrorAction SilentlyContinue
    Set-ExecutionPolicy Unrestricted -Scope LocalMachine -Force -ErrorAction SilentlyContinue
    Write-Log "INFO" "Finished setting execution policy"
    #endregion
    #######################################

    #######################################
    #region Enable PS-Remoting
    #######################################
    Write-Log "INFO" "Enabling PowerShell remoting"
    Enable-PSRemoting -SkipNetworkProfileCheck -Force -Confirm:$false
    Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WSMAN\Service\' -Name 'allow_unencrypted' -Value 0x1
    Set-Item WSMan:\localhost\Client\TrustedHosts * -Force
    Set-Item WSMan:\localhost\Client\AllowUnencrypted $true -Force
    Restart-Service winrm
    Write-Log "INFO" "Finished enabling PowerShell remoting"
    #endregion
    #######################################

    #######################################
    #region Enable CredSSP
    #######################################
    Write-Log "INFO" "Enabling CredSSP authentication"
    Enable-WSManCredSSP -Role Server -Force | Out-Null
    Enable-WSManCredSSP -Role Client -DelegateComputer * -Force | Out-Null
    Write-Log "INFO" "Finished enabling CredSSP authentication"
    #endregion
    #######################################

    #######################################
    #region Network adapters
    #######################################
    Write-Log "INFO" "Renaming network adapters"
    foreach ($netAdapter in Get-NetAdapter) {
        Write-Log "INFO" "Renaming network adapter '$($netAdapter.Name)'"
        $networkAdapterName = (Get-NetAdapterAdvancedProperty -Name $netAdapter.Name -DisplayName 'Hyper-V Network Adapter Name' -ErrorAction SilentlyContinue).DisplayValue
        if ($networkAdapterName -and $netAdapter.Name -ne $networkAdapterName) {
            Write-Log "INFO" "Renaming network adapter '$($netAdapter.Name)' to '$networkAdapterName'"
            Rename-NetAdapter -Name $netAdapter.Name -NewName $networkAdapterName
            Write-Log "INFO" "Finished renaming network adapter '$($netAdapter.Name)' to '$networkAdapterName'"
        }
        else {
            Write-Log "INFO" "Skipping renaming network adapter '$($netAdapter.Name)'"
        }
    }
    Write-Log "INFO" "Finished renaming network adapters"
    #endregion
    #######################################

    #######################################
    #region Configure DSC Pull
    #######################################
    Write-Log "INFO" "Retrieving DSC details..."
    $dscDiscovery = Discover-DscPullServer -Server $DiscoveryServer
	if (-not $dscDiscovery) {
		Write-Log "INFO" "Unable to retrieve DSC details; skipped configuration for DSC Pull."
	}
	else {
		$pullServerUrl = $dscDiscovery.DscPullServerUrl
		$registrationKey = $dscDiscovery.DscPullServerRegistrationKey
		$configurationName = $dscDiscovery.DscConfigurationName

		Write-Log "INFO" "DSC Pull Server Url: '$pullServerUrl'"
		Write-Log "INFO" "DSC Registration Key: '$registrationKey'"
		Write-Log "INFO" "DSC Configuration Name: '$configurationName'"
		Write-Log "INFO" "Finished retrieving DSC details"

		Write-Log "INFO" "Configuring DSC Pull"
		[DSCLocalConfigurationManager()]
		Configuration DSCPullNode {
			param (
				[string]$PullServerUrl,
				[string]$RegistrationKey,
				[string]$ConfigurationName
			)

			Node localhost {
				Settings {
					ConfigurationMode = 'ApplyAndAutoCorrect'
					ConfigurationModeFrequencyMins = 15
					RefreshMode = 'Pull'
					RefreshFrequencyMins = 30
					RebootNodeIfNeeded = $true
				}

				ConfigurationRepositoryWeb DSCPullServer {
					ServerURL = $PullServerUrl
					AllowUnsecureConnection = $true
					RegistrationKey = $RegistrationKey
					ConfigurationNames = @($ConfigurationName)
				}

				ReportServerWeb DSCReportServer {
					ServerURL = $PullServerUrl
					AllowUnsecureConnection = $true
					RegistrationKey = $RegistrationKey
				}
			}
		}

		$configurationPath = Join-Path -Path $PSScriptRoot -ChildPath 'DSCPullNode'
		$configurationData = @{
			AllNodes = @(
				@{
					NodeName = '*'
					PSDscAllowPlainTextPassword = $true
					RebootNodeIfNeeded = $true
				}
			)
		}
		Write-Log "INFO" "Generating configuration"
		DSCPullNode -PullServerUrl $pullServerUrl -RegistrationKey $registrationKey -ConfigurationName $configurationName -OutputPath $configurationPath -ConfigurationData $configurationData
		Write-Log "INFO" "Starting configuration"
		Set-DscLocalConfigurationManager -Path $configurationPath -ComputerName localhost -Force -Verbose
		Write-Log "INFO" "Finished configuring DSC Pull"

		Write-Log "INFO" "Applying configuration (from pull server)"
		Update-DscConfiguration -Wait -Verbose
		Write-Log "INFO" "Finished applying configution"
	}
    #endregion
    #######################################

    Write-Log "INFO" "Finished setup-complete script"
}
catch {
    Write-Log "ERROR" $_
}
