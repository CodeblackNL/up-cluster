
function Install-Docker {
    param (
        [string]
        $InstallFolderPath = (Join-Path -Path $env:windir -ChildPath 'system32'),

        [Hashtable]
        $DaemonParameters
    )

    Write-Host "Starting installing docker..."

    $dockerDaemonFilePath = Join-Path -Path $InstallFolderPath -ChildPath 'dockerd.exe'
    $dockerClientFilePath = Join-Path -Path $InstallFolderPath -ChildPath 'docker.exe'
    $serviceName = 'Docker'
    $featureName = 'Containers'

    # TODO: install Containers feature
    if (Get-Command -Name 'Get-WindowsFeature' -ErrorAction SilentlyContinue) {
        $feature = Get-WindowsFeature -Name $featureName
        if ($feature) {
            Write-Host "Found feature '$($feature.Name)' ($($feature.InstallState))."
            if ($feature.InstallState -ne 'Installed') {
                Write-Warning "Feature '$($feature.Name)' is not installed."
                #Install-WindowsFeature –Name $featureName
            }
        }
        else {
            Write-Error "Feature '$featureName' not available."
        }
    }
    elseif (Get-Command -Name 'Get-WindowsOptionalFeature' -ErrorAction SilentlyContinue) {
        $feature = Get-WindowsOptionalFeature –Online -FeatureName $featureName
        if ($feature) {
            Write-Host "Found feature '$($feature.FeatureName)' ($($feature.State))."
            if ($feature.State -ne 'Enabled') {
                Write-Warning "Feature '$($feature.FeatureName)' is not installed."
                #Enable-WindowsOptionalFeature –Online –FeatureName $featureName
            }
        }
        else {
            Write-Error "Feature '$featureName' not available."
        }
    }

    Write-Host "Installing docker daeamon..."
    Copy-Item -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\Files\dockerd.exe') -Destination $dockerDaemonFilePath -Force

    Write-Host "Installing docker client..."
    Copy-Item -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\Files\docker.exe') -Destination $dockerClientFilePath -Force

    if ($DaemonParameters -and $DaemonParameters.Count -gt 0) {
        Write-Host "Writing docker daeamon configuration..."
        New-DockerDaemonConfiguration -ConfigurationParameters $DaemonParameters
    }
    else {
        Write-Host "No parameters provided; skipped writing docker daeamon configuration."
    }

    Write-Host "Registering docker daeamon as a service..."
    Start-Process -FilePath $dockerDaemonFilePath -ArgumentList '--register-service' -Wait
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-Error "Service '$serviceName' does not exist; registration failed."
    }
    else {
        Write-Host "Starting docker daeamon service..."
        Start-Service -Name $serviceName
    }

    Write-Host "Finished installing docker."
}
