
$toolsDir = "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)"

Write-Host "Uninstalling '$($env:chocolateyPackageName) $($env:chocolateyPackageVersion)'..."

$uninstallFilePath = 'C:\Program Files\Microsoft Service Fabric\bin\Fabric\Fabric.Code\CleanFabric.ps1'
if (Test-Path -Path $uninstallFilePath -PathType Leaf) {
    . $uninstallFilePath
}