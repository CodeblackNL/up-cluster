[CmdletBinding()]
param (
	[Parameter(Mandatory = $true)]
	[string]$Drive,
	[Parameter(Mandatory = $false)]
	[switch]$Force
)

$partition = Get-Partition -DriveLetter $Drive -ErrorAction SilentlyContinue
if (-not $partition) {
	throw "Drive '$Drive' does not exist."
}

if (($partition | Get-Disk).BusType -ne 'USB') {
	throw "Drive '$Drive' is not a USB disk."
}

$drivePath = "$($Drive):\"
if (-not $Force.IsPresent -and @(Get-ChildItem -Path $drivePath).Length -gt 0) {
	throw "Drive '$Drive' is not empty."
}

$sourceFolderPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Files.Disk'
$imagesFolderPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Images'

Write-Verbose "Copying files..."
& robocopy.exe "$sourceFolderPath" "$drivePath" /E /NJH /NJS /NFL /NDL

Write-Verbose "Copying 'boot.wim' image..."
$destinationFilePath = Join-Path -Path $drivePath -ChildPath 'Provisioning\Images\boot.wim'
if (-not (Test-Path -Path $destinationFilePath -PathType Leaf)) {
    Copy-Item -Force `
        -Path (Join-Path -Path $imagesFolderPath -ChildPath 'boot.wim') `
        -Destination (Split-Path -Path $destinationFilePath -Parent)
}
else {
    Write-Verbose "'boot.wim' image already copied."
}
