
$sourceFolderPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Modules'
$modulesSourcePath = Join-Path -Path $PSScriptRoot -ChildPath '..\Files.Disk\InstallationShare\Modules'
$destinationFolderPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Files.Disk\Provisioning\Modules'

Push-Location -Path $modulesSourcePath

Get-ChildItem -Path $sourceFolderPath -Filter '*.nuspec' -Recurse |% {
    choco pack $_.FullName
	
	Get-ChildItem -Path $modulesSourcePath -Filter "$($_.BaseName).*.nupkg" | Copy-Item  -Destination $destinationFolderPath
}

Pop-Location

#Get-ChildItem -Path 'D:\Projects.GitHub\chocolatey-oneget-provider\src' -Filter '*.nupkg' `
#    | Copy-Item -Destination $modulesSourcePath -Force

#Get-ChildItem -Path $modulesSourcePath -Filter '*.nupkg' `
#    | Copy-Item -Destination '\\10.42.64.1\InstallationShare\Modules' -Force
