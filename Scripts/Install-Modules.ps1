$modulesPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Files.Disk\Provisioning\Modules'
$destination = Join-Path -Path $env:ProgramFiles -ChildPath 'WindowsPowerShell\Modules'
Write-Host "Installing modules..."

Get-ChildItem -Path "$modulesPath\*" -include '*.nupkg','*.zip' | Sort Name | ForEach-Object {
    if ($_.BaseName -match '(?<name>\D*)\.(?<version>\d*.\d*(.\d*(.\d*)?)?)') {
        Write-Host "Installing module '$($_.BaseName)'"
        if ([System.IO.Path]::GetExtension($_.FullName) -ne '.zip') {
            $zipFilePath = Join-Path -Path $_.Directory -ChildPath "$($_.BaseName).zip"
            Rename-Item -Path $_.FullName -NewName $zipFilePath
        }
        else {
            $zipFilePath = $_.FullName
        }

        $destinationPath = Join-Path -Path $destination -ChildPath "$($Matches.name)\$($Matches.version)"
        New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
        Expand-Archive -Path $zipFilePath -DestinationPath $destinationPath -Force

        Get-ChildItem -Path $destinationPath | Where-Object { $_.BaseName -in 'package', '_rels','[Content_Types]' } | Remove-Item -Recurse -Force

        if ($zipFilePath -ne $_.FullName) {
            Rename-Item -Path $zipFilePath -NewName $_.FullName
        }
    }
}
