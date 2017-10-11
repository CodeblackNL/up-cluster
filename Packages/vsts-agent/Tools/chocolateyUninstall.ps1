
Write-Host "Uninstalling '$($env:chocolateyPackageName) $($env:chocolateyPackageVersion)'..."

. (Join-Path -Path $PSScriptRoot -ChildPath '..\Scripts\Get-ChocolateyParameters.ps1')

$parameters = Get-ChocolateyParameters -PackageParameters $env:chocolateyPackageParameters

$installDirectory = $parameters.'install-directory'
if (-not $installDirectory) {
    $installDirectory = 'C:\agent'
}

if (Test-Path -Path $installDirectory -PathType Container) {
    $configCommandFilePah = Join-Path -Path $installDirectory -ChildPath 'config.cmd'
    if (Test-Path -Path $configCommandFilePah -PathType Leaf) {
        Start-Process -FilePath $configCommandFilePah -ArgumentList 'remove' -Wait -ErrorAction SilentlyContinue
    }

    Remove-Item -Path $installDirectory -Recurse -Force
}
