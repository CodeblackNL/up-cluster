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
        Add-content $logFilePath -value $formattedMessage
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
        Write-Log "DEBUG" "Received: $response.Content"
        return ConvertFrom-Json $response.Content
    }
}

#endregion
#######################################

try {
    Write-Log "INFO" "Starting script '$($MyInvocation.InvocationName)'"
    Write-Log "INFO" "Running as '$($env:USERNAME)'"

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
		Write-Log "INFO" "DSC COnfiguration Name: '$configurationName'"
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
}
catch {
    Write-Log "ERROR" $_
}
