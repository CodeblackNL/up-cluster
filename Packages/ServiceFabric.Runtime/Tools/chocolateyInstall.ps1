
$toolsDir = "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)"

. (Join-Path -Path $toolsDir -ChildPath 'chocolateyUninstall.ps1')

Write-Host "Installing '$($env:chocolateyPackageName) $($env:chocolateyPackageVersion)'..."

$installFilePath = (Get-ChildItem -Path (Join-Path -Path $toolsDir -ChildPath '..\Files') -Filter 'MicrosoftServiceFabric.*.exe').FullName
Write-Host "Executing '$installFilePath'..."
Install-ChocolateyInstallPackage `
    -PackageName 'Microsoft Azure Service Fabric Runtime' `
    -FileType    'exe' `
    -File        $installFilePath `
    -SilentArgs  '/AcceptEULA'
