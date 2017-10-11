
$sourceFolderPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Packages'
$packagesSourcePath = Join-Path -Path $PSScriptRoot -ChildPath '..\Files.Disk\InstallationShare\Packages'

Push-Location -Path $packagesSourcePath

Get-ChildItem -Path $sourceFolderPath -Filter '*.nuspec' -Recurse |% {
    choco pack $_.FullName
}

Pop-Location

#Get-ChildItem -Path $packagesSourcePath -Filter '*.nupkg' `
#    | Copy-Item -Destination '\\10.42.64.1\InstallationShare\Packages' -Force
