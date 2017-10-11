
Write-Host "Installing '$($env:chocolateyPackageName) $($env:chocolateyPackageVersion)'..."

. (Join-Path -Path $PSScriptRoot -ChildPath '..\Scripts\Get-ChocolateyParameters.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Scripts\New-DockerDaemonConfiguration.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Scripts\Install-Docker.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Scripts\Uninstall-Docker.ps1')

$parameters = Get-ChocolateyParameters -PackageParameters $env:chocolateyPackageParameters

Uninstall-Docker
Install-Docker -DaemonParameters $parameters
