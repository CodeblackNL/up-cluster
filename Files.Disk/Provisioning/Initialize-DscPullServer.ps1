$scriptFolder = $PSScriptRoot
$logFilePath = Join-Path -Path $scriptFolder -ChildPath 'log.txt'

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

function Convert-PSObjectToHashtable {
    param (
        [Parameter(  
             Position = 0,   
             ValueFromPipeline = $true,  
             ValueFromPipelineByPropertyName = $true  
         )]
        [object]$InputObject
    )

    if (-not $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        $output = @(
            foreach ($item in $InputObject) {
                Convert-PSObjectToHashtable $item
            }
        )

        Write-Output -NoEnumerate $output
    }
    elseif ($InputObject -is [psobject]) {
        $output = @{}
        $InputObject | Get-Member -MemberType *Property | % { 
            $output.($_.name) = Convert-PSObjectToHashtable $InputObject.($_.name)
        } 
        $output
    }
    else {
        $InputObject
    }
}

#endregion
#######################################

try {
    Write-Log "INFO" "Starting setup-complete script in '$scriptFolder'"
    Write-Log "INFO" "Running as '$($env:USERNAME)'"

    #######################################
    #region Install modules
    #######################################
    $modulesPath = Join-Path -Path $scriptFolder -ChildPath 'Modules'
    if (Test-Path -Path $modulesPath -PathType Container) {
        $destination = Join-Path -Path $env:ProgramFiles -ChildPath 'WindowsPowerShell\Modules'
        Write-Log "INFO" "installing modules from '$modulesPath' to '$destination'"
        Get-ChildItem -Path "$modulesPath\*" -include '*.nupkg','*.zip' |% {
            if ($_.BaseName -match '(?<name>\D*)\.(?<version>\d*.\d*(.\d*(.\d*)?)?)') {
                $module = Get-Module -Name $Matches.name -ListAvailable -ErrorAction SilentlyContinue | Where-Object { $_.Version -eq $Matches.version }
                if (-not $module) {
                    Write-Log "INFO" "Installing module '$($_.BaseName)'"
                    if ([System.IO.Path]::GetExtension($_.FullName) -ne '.zip') {
                        $zipFilePath = Join-Path -Path $_.Directory -ChildPath "$($_.BaseName).zip"
                        Rename-Item -Path $_.FullName -NewName $zipFilePath
                    }
                    else {
                        $zipFilePath = $_.FullName
                    }

                    $destinationPath = Join-Path -Path $destination -ChildPath "$($Matches.name)\$($Matches.version)"
                    New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
                    Expand-Archive -Path $zipFilePath -DestinationPath $destinationPath -Force

                    get-childitem -path $destinationPath |? { $_.BaseName -in 'package', '_rels','[Content_Types]' } | Remove-Item -Recurse -Force

                    if ($zipFilePath -ne $_.FullName) {
                        Rename-Item -Path $zipFilePath -NewName $_.FullName
                    }
                }
                else {
                    Write-Log "INFO" "Module '$($_.BaseName)' already installed"
                }
            }
        }
    }
    else {
        Write-Log "INFO" "Modules path '$modulesPath' not found"
    }
    #endregion
    #######################################

    #######################################
    #region Update LocalConfigurationManager
    #######################################
    Write-Log "INFO" "Updating LocalConfigurationManager with RebootNodeIfNeeded"
    configuration LCM_RebootNodeIfNeeded {
        node localhost {
            LocalConfigurationManager {
                RebootNodeIfNeeded = $true
            }
        }
    }

    LCM_RebootNodeIfNeeded -OutputPath "$scriptFolder\LCM_RebootNodeIfNeeded" | Out-Null
    Set-DscLocalConfigurationManager -Path "$scriptFolder\LCM_RebootNodeIfNeeded" -Verbose -ComputerName localhost
    Write-Log "INFO" "Finished updating LocalConfigurationManager with RebootNodeIfNeeded"
    #endregion
    #######################################

    #######################################
    #region Load configuration
    #######################################
    Write-Log "INFO" "Loading configuration"
    $configurationFilePath = @(
        'D:\Provisioning\cluster.json'
        'D:\Provisioning\environment.json'
        'C:\_provisioning\cluster.json'
        'C:\_provisioning\environment.json'
    ) | Where-Object { Test-Path -Path $_ -PathType Leaf } | Select -First 1
    if (Test-Path -Path $configurationFilePath -PathType Leaf) {
        $environmentConfiguration = Convert-PSObjectToHashtable -InputObject (Get-Content -Path $configurationFilePath -Raw | ConvertFrom-Json)
        Write-Log "INFO" "Finished loading configuration ('$configurationFilePath')"
    }
    else {
        Write-Log "INFO" "No configuration found ('$configurationFilePath')"
    }

    if ($environmentConfiguration) {
        $nodeConfiguration = $environmentConfiguration.Nodes `
            | Where-Object { $_.Roles | Where-Object { $_.Name -eq 'DscPullserver' } } `
            | Select-Object -First 1
        if ($nodeConfiguration) {
            $nodeConfiguration.Environment =$environmentConfiguration
        }
    }
    #endregion
    #######################################

    #######################################
    #region Apply configuration
    #######################################
    $dscFilePath = Join-Path -Path $scriptFolder -ChildPath 'LabEnvironment.ps1'
    if (-not $nodeConfiguration) {
        Write-Log "WARNING" "No node-configuration; skipped applying DSC-configuration"
    }
    elseif (-not (Test-Path -Path $dscFilePath)) {
        Write-Log "WARNING" "No DSC-configuration; skipped applying DSC-configuration"
    }
    else {
        Write-Log "INFO" "Preparing configuration for DSC"
        $nodeConfiguration.NodeName = 'localhost'
        $nodeConfiguration.PSDscAllowPlainTextPassword = $true
        $nodeConfiguration.PSDscAllowDomainUser = $true

        $configurationData = @{
            AllNodes = @($nodeConfiguration)
        }

        Write-Log "INFO" "Loading configuration"
        . $dscFilePath
        Write-Log "INFO" "Generating configuration"
        $outputPath = Join-Path -Path $PSScriptRoot -ChildPath "$([System.IO.Path]::GetFileNameWithoutExtension($dscFilePath))_DSC"
        LabEnvironment -ConfigurationData $configurationData -OutputPath $outputPath | Out-Null
        Write-Log "INFO" "Applying configuration"
        Start-DscConfiguration –Path $outputPath –Wait -Force –Verbose | Out-Null
        Write-Log "INFO" "Finished applying configuration"
    }
    #endregion
    #######################################

    Write-Log "INFO" "Finished setup-complete script"
}
catch {
    Write-Log "ERROR" $_
}
