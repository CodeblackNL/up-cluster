param (
	[Parameter(Mandatory = $true)]
	[string]$Drive,
	[Parameter(Mandatory = $false)]
    [ValidateSet('Core', 'GUI')]
	[string]$Edition = 'GUI',
	[Parameter(Mandatory = $false)]
	[string]$Filter,
	[Parameter(Mandatory = $false)]
	[string]$UnattendFilePath = (Join-Path -Path $PSScriptRoot -ChildPath '..\Provisioning.Disk\WdsClientUnattend\UP-STD-USB.xml')
)

$partition = Get-Partition -DriveLetter $Drive -ErrorAction SilentlyContinue
if (-not $partition) {
	throw "Drive '$Drive' does not exist."
}

if (($partition | Get-Disk).BusType -ne 'USB') {
	throw "Drive '$Drive' is not a USB disk."
}

$drivePath = "$($Drive):\"
$isInstallationDisk = $false
if (-not (Test-Path -Path (Join-Path -Path $drivePath -ChildPath 'sources') -PathType Container)) {
	throw "Drive '$Drive' is not an installation disk."
}

if (-not (Test-Path -Path $UnattendFilePath -PathType Leaf)) {
	throw "Unattend file '$UnattendFilePath' does not exist."
}

if ($Edition -eq 'Core') {
    $imageFilter = '*_CORE.wim'
}
else {
    $imageFilter = '*_GUI.wim'
}

$imageFile = Get-ChildItem '..\Provisioning.Disk\Images' -Filter $imageFilter
if ($Filter) {
    $imageFile = $imageFile | Where-Object { $_.Name -match $Filter }
}

if (@($imageFile).Length -eq 0) {
	throw "No image found for edition '$Edition' and filter '$Filter'."
}
elseif (@($imageFile).Length -gt 1) {
	throw "Multiple images found for edition '$Edition' and filter '$Filter'."
}

Write-Verbose "Copying 'autounattend.xml' file (from '$UnattendFilePath')..."
Copy-Item -Path $UnattendFilePath -Destination (Join-Path -Path $drivePath -ChildPath 'autounattend.xml') -Force

$imageFilePath = Join-Path -Path $drivePath -ChildPath 'sources\install.wim'
Write-Verbose "Removing original 'install.wim'..."
Remove-Item -Path $imageFilePath -Force
Write-Verbose "Copying 'install.wim' file (from '$($imageFile.FullName)')..."
Copy-Item -Path $imageFile.FullName -Destination $imageFilePath -Force
