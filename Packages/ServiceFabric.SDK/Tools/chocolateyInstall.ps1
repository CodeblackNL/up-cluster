
$toolsDir = "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)"

. (Join-Path -Path $toolsDir -ChildPath 'chocolateyUninstall.ps1')

Write-Host "Installing '$($env:chocolateyPackageName) $($env:chocolateyPackageVersion)'..."

$installFilePath = (Get-ChildItem -Path (Join-Path -Path $toolsDir -ChildPath '..\Files') -Filter 'MicrosoftServiceFabricSDK.*.msi').FullName
Write-Host "Executing '$installFilePath'..."
Install-ChocolateyInstallPackage `
    -PackageName 'Microsoft Azure Service Fabric SDK' `
    -FileType    'msi' `
    -File        $installFilePath `
    -SilentArgs  '/quiet /qn /norestart'
