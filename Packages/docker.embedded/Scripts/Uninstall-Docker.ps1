
function Uninstall-Docker {
    param (
        [string]
        $InstallFolderPath = (Join-Path -Path $env:windir -ChildPath 'system32')
    )

    Write-Host "Starting uninstalling docker..."

    $dockerDaemonFilePath = Join-Path -Path $InstallFolderPath -ChildPath 'dockerd.exe'
    $dockerClientFilePath = Join-Path -Path $InstallFolderPath -ChildPath 'docker.exe'
    $serviceName = 'Docker'

    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($service) {
        Write-Host "Found service '$serviceName' ($($service.Status))."
        if ($service.Status -ne 'Stopped') {
            Write-Host "Stopping service '$serviceName'..."
            Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
            Write-Host "Service '$serviceName' stopped."
        }
    }

    if (Test-Path -Path $dockerDaemonFilePath -PathType Leaf) {
        Write-Host "Found docker daeamon ('$dockerDaemonFilePath')."
        if ($service) {
            Write-Host "Unregistering docker daeamon as a service..."
            Start-Process -FilePath $dockerDaemonFilePath -ArgumentList '--unregister-service' -Wait
        }

        Write-Host "Killing any docker daeamon processes..."
        Get-Process -Name ([System.IO.Path]::GetFileNameWithoutExtension($dockerDaemonFilePath)) -ErrorAction SilentlyContinue | Stop-Process -Force

        Write-Host "Removing docker daeamon..."
        Remove-Item -Path $dockerDaemonFilePath -Force

        Write-Host "Finished uninstalling docker daeamon."
    }

    if (Test-Path -Path $dockerClientFilePath -PathType Leaf) {
        Write-Host "Killing any docker client processes..."
        Get-Process -Name ([System.IO.Path]::GetFileNameWithoutExtension($dockerClientFilePath)) -ErrorAction SilentlyContinue | Stop-Process -Force

        Write-Host "Removing docker client..."
        Remove-Item -Path $dockerClientFilePath -Force

        Write-Host "Finished uninstalling docker client."
    }

    Write-Host "Finished uninstalling docker."
}
