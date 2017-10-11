
Write-Host "Uninstalling '$($env:chocolateyPackageName) $($env:chocolateyPackageVersion)'..."

. (Join-Path -Path $PSScriptRoot -ChildPath '..\Scripts\Get-ChocolateyParameters.ps1')
. (Join-Path -Path $PSScriptRoot -ChildPath '..\Scripts\Uninstall-Docker.ps1')

Uninstall-Docker
