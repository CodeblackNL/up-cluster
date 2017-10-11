param (
    [Parameter(Mandatory = $true)]
    [ValidateSet('Core', 'GUI')]
    [string]$Edition,
    [Parameter(Mandatory = $false)]
    [switch]$NoFiles
)

function New-UpWindowsImage {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SourceImageFilePath,
        [Parameter(Mandatory = $false)]
        [int]$SourceImageIndex = 1,
        [Parameter(Mandatory = $true)]
        [string]$DestinationImageFilePath,
        [Parameter(Mandatory = $false)]
        [string]$MountPath = (Join-Path -Path (Split-Path -Path $SourceImageFilePath -Parent) -ChildPath 'Mount'),

        [Parameter(Mandatory = $false)]
        [string]$DriversPath,

        [Parameter(Mandatory = $false)]
        [string[]]$UpdatesPath,

        [Parameter(Mandatory = $false)]
        [string[]]$FilesPath,
        [Parameter(Mandatory = $false)]
        [string]$FilesRootPath = '',

        [Parameter(Mandatory = $false)]
        [string]$SetupCompleteScriptText
    )

    Write-Host "Image '$([System.IO.Path]::GetFileName($DestinationImageFilePath))'" -ForegroundColor Yellow
    Write-Host "  Using base-image $SourceImageIndex from '$([System.IO.Path]::GetFileName($SourceImageFilePath))'"
    Write-Host "  Mounting at        '$MountPath'"
    if ($FilesPath) {
        Write-Host "  Copying files from '$FilesPath'"
    }
    Write-Host

    $useTempMountPath = -not (Test-Path -Path $MountPath -PathType Container)
    if ($useTempMountPath) {
        Write-Host "Creating temporary mount path..."
        New-Item -Path $MountPath -ItemType Directory -Force | Out-Null
    }

    if (Test-Path -Path $DestinationImageFilePath -PathType Leaf) {
        Write-Host "  Deleting existing image..."
        Remove-Item -Path $DestinationImageFilePath -Force
    }

    try {
        Write-Host "  Creating image..."
        Mount-WindowsImage -ImagePath $SourceImageFilePath -Path $MountPath -Index $SourceImageIndex | Out-Null

        if ($DriversPath) {
            Write-Host "  Add drivers into image..."
	        #dism /image:$MountPath /add-driver:$DriversPath /recurse /ForceUnsigned
            Add-WindowsDriver –Path $MountPath –Driver $DriversPath -Recurse -ForceUnsigned
        }

        if ($UpdatesPath) {
            Write-Host "  Add updates into image..."
            foreach ($updatePath in $UpdatesPath) {
                Write-Host "  > '$updatePath'..."
                Add-WindowsPackage -Path $MountPath -PackagePath $updatePath
            }

            Write-Host "  cleaning component-store in image..."
            # Dism /Image:$MountPath /Cleanup-Image /AnalyzeComponentStore
            Dism /Image:$MountPath /Cleanup-Image /StartComponentCleanup /ResetBase
        }

        if ($FilesPath) {
            $filesDestinationPath = $MountPath
            if ($FilesRootPath) {
                $filesDestinationPath = Join-Path -Path $MountPath -ChildPath $FilesRootPath
            }
            if (-not (Test-Path -Path $filesDestinationPath -PathType Container)) {
                New-Item -Path $filesDestinationPath -ItemType Directory -Force | Out-Null
            }
            Write-Host "  Copying files into image..."
            foreach ($path in $FilesPath) {
                Write-Host "  > '$path'..."
                Copy-Item -Path (Join-Path -Path $path -ChildPath '*') -Destination $filesDestinationPath -Recurse -Force
            }
        }

        if ($SetupCompleteScriptText) {
            $setupCompleteFilePath = Join-Path -Path $MountPath -ChildPath 'Windows\Setup\Scripts\SetupComplete.cmd'
            $setupCompleteFolderPath = Split-Path -Path $setupCompleteFilePath -Parent
            if (-not (Test-Path -Path $setupCompleteFolderPath -PathType Container)) {
                New-Item -Path $setupCompleteFolderPath -ItemType Directory -Force | Out-Null
            }
            $SetupCompleteScriptText | Set-Content -Path $setupCompleteFilePath
        }

        Write-Host "  Saving image..."
        New-WindowsImage -CapturePath $MountPath -Name ([System.IO.Path]::GetFileNameWithoutExtension($DestinationImageFilePath)) -ImagePath $DestinationImageFilePath -Verify
    }
    finally {
        try {
            Dismount-WindowsImage -Path $MountPath -Discard -ErrorAction SilentlyContinue
        }
        catch {
        }

        if ($useTempMountPath) {
            Write-Host "Deleting temporary mount path..."
            Remove-Item -Path $MountPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

$wimSourceFilePath = (Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\Images') -Filter 'install.wim').FullName
if (-not $wimSourceFilePath) {
    throw "Source image 'install.wim' not found."
}

$wimDestinationFolderPath = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..\Files.Disk\Provisioning\Images'))
$driversPath = [System.IO.Path]::GetFullPath((Join-Path -path $PSScriptRoot -ChildPath '..\Images\Drivers'))
$updatesFolderPath = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..\Images\Updates'))
$filesPath = [System.IO.Path]::GetFullPath((Join-Path -path $PSScriptRoot -ChildPath '..\Files.Node'))

$updates = (Get-ChildItem -Path $updatesFolderPath -File | Where-Object { $_.Name -notmatch '\.md' }).FullName

switch ($Edition) {
    'Core' { $imageIndex = 1 }
    'GUI'  { $imageIndex = 2 }
}

$fileName = "W2016_STD_$($Edition.ToUpper())"
$params = @{}
if (-not $NoFiles.IsPresent) {
    $fileName += '_UP'
    $params.FilesPath  = $filesPath
    $params.SetupCompleteScriptText = 'powershell -File C:\_provisioning\SetupComplete.ps1 -ExecutionPolicy Unrestricted > C:\_provisioning\SetupComplete.txt'
}

$wimDestinationFilePath = Join-Path -path $wimDestinationFolderPath -ChildPath "$fileName.wim"
if (Test-Path -Path $wimDestinationFilePath -PathType Leaf) {
    throw "Image '$wimDestinationFilePath' already exists; delete the file and try again."
}

New-Item -Path $wimDestinationFolderPath -ItemType Directory -ErrorAction SilentlyContinue | Out-Null

New-UpWindowsImage `
    -SourceImageFilePath $wimSourceFilePath `
    -SourceImageIndex $imageIndex `
    -DestinationImageFilePath $wimDestinationFilePath `
    -DriversPath $driversPath `
    -UpdatesPath $updatesPath `
    @params
