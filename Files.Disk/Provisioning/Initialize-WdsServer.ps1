#######################################
#region Load configuration
#######################################
$configurationFilePath = @(
    'D:\Provisioning\cluster.json'
    'D:\Provisioning\environment.json'
    'C:\_provisioning\cluster.json'
    'C:\_provisioning\environment.json'
) | Where-Object { Test-Path -Path $_ -PathType Leaf } | Select -First 1
if (-not $configurationFilePath) {
    throw 'Configuration file not found.'
}
$environmentConfiguration = Get-Content -Path $configurationFilePath -Raw | ConvertFrom-Json
$nodeConfiguration = $environmentConfiguration.Nodes `
    | Where-Object { $_.Roles | Where-Object { $_.Name -eq 'WdsServer' } } `
    | Select-Object -First 1
if ($nodeConfiguration) {
    $nodeConfiguration | Add-Member -MemberType NoteProperty -Name 'Environment' -Value $environmentConfiguration
}

$wdsRole = $nodeConfiguration.Roles | Where-Object { $_.Name -eq 'WdsServer' }
if ($wdsRole) {
    $wdsRemoteInstallPath = $wdsRole.Path
}
if (-not $wdsRemoteInstallPath) {
    if (Test-Path -Path 'D:\') {
        $wdsRemoteInstallPath = 'D:\RemoteInstall'
    }
    else {
        $wdsRemoteInstallPath = 'C:\RemoteInstall'
    }
}
#endregion
#######################################

#######################################
#region WDS
#######################################
$wdsServiceName = 'WDSServer'
$wdsService = Get-Service -Name $wdsServiceName -ErrorAction SilentlyContinue
if (-not $wdsService -or $wdsService.StartType -ne 'Automatic') {
    Write-Host 'Initializing WDS...'
    Start-Process -FilePath 'wdsutil' -ArgumentList '/Initialize-Server','/Standalone',"/RemInst:$($wdsRemoteInstallPath)" -Wait
}
else {
    Write-Host 'WDS already initialized.'
}

if ((Get-Service -Name $wdsServiceName).Status -ne 'Running') {
    Write-Host 'Starting WDS service...'
    Start-Service -Name $wdsServiceName
}
else {
    Write-Host 'WDS service already running.'
}

Write-Host 'Configuring WDS Client & PXE policies...'
$argumentList =  '/Set-Server',
                 '/AnswerClients:All',   # /AnswerClients:Known
                 '/PxePromptPolicy','/Known:NoPrompt','/New:NoPrompt',
                 '/WdsUnattend', '/Policy:Enabled'
Start-Process -FilePath 'wdsutil' -ArgumentList $argumentList -Wait

#endregion
#######################################

#######################################
#region boot-image
#######################################
$bootImagePath = 'Boot\x64\Images\boot.wim'
if (-not (Get-WdsBootImage -ImageName 'Microsoft Windows Setup (x64)')) {
    Write-Host 'Importing boot-image...'
    $null = Import-WdsBootImage -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Images\boot.wim')
}
else {
    Write-Host 'Boot-image already present.'
}
Write-Host 'Configuring WDS default boot image...'
$argumentList =  '/Set-Server',"/BootImage:$bootImagePath",'/Architecture:x64',"/BootImage:$bootImagePath",'/Architecture:x64uefi'
Start-Process -FilePath 'wdsutil' -ArgumentList $argumentList -Wait

#endregion
#######################################

#######################################
#region unattend-files
#######################################
$unattendSourcePath = Join-Path -Path $PSScriptRoot -ChildPath 'WdsClientUnattend'
$unattendDestinationPath = Join-Path -Path $wdsRemoteInstallPath -ChildPath 'WdsClientUnattend'

$unattendFiles = @{
    CoreEdition = 'UP-STD-CORE-amd64-wim.xml'
    GuiEdition = 'UP-STD-GUI-amd64-wim.xml'
}

foreach ($key in $unattendFiles.Keys) {
    $unattendFileName = $unattendFiles.$key

    $unattendSourceFilePath = Join-Path -Path $unattendSourcePath -ChildPath $unattendFileName
    $unattendDestinationFilePath = Join-Path -Path $unattendDestinationPath -ChildPath $unattendFileName

    if (-not (Test-Path -Path $unattendDestinationFilePath -PathType Leaf)) {
        Write-Host "Installing unattend-file '$unattendFileName'..."
        Copy-Item -Path $unattendSourceFilePath -Destination $unattendDestinationPath -Force | Out-Null
    }
    else {
        Write-Host "Unattend-file '$unattendFileName' already installed"
    }
}
#endregion
#######################################

#######################################
#region install-images
#######################################
$wimImageGroupName = 'W2016 WIM'
if (-not (Get-WdsInstallImageGroup -Name $wimImageGroupName -ErrorAction SilentlyContinue)) {
    Write-Host "Creating install-image group '$wimImageGroupName'..."
    $null = New-WdsInstallImageGroup -Name $wimImageGroupName
}
else {
    Write-Host "Install-image group '$wimImageGroupName' already present."
}

$coreImageFile = Get-ChildItem (Join-Path -Path $PSScriptRoot -ChildPath '\Images') -Filter '*_CORE_*' | Sort-Object Name | Select-Object -Last 1
if ($coreImageFile) {
    $coreImageName = [System.IO.Path]::GetFileNameWithoutExtension(($coreImageFile.FullName))
    Write-Host 'Checking ''Core'' install-image '$coreImageName'...'
    if (-not (Get-WdsInstallImage -ImageName $coreImageName -ImageGroup $wimImageGroupName -ErrorAction SilentlyContinue)) {
        Write-Host 'Importing ''Core'' install-image '$($coreImageFile.FullName)'...'
        if ($unattendFiles.CoreEdition) {
            $unattendFilePath = (Get-ChildItem -Path $unattendDestinationPath | Where-Object { $_.Name -eq $unattendFiles.CoreEdition }).FullName
            Write-Host ' with unattend-file '$unattendFilePath'...'
            Import-WdsInstallImage -Path $coreImageFile.FullName -ImageGroup $wimImageGroupName -UnattendFile $unattendFilePath | Out-Null
        }
        else {
            Import-WdsInstallImage -Path $coreImageFile.FullName -ImageGroup $wimImageGroupName | Out-Null
        }
    }
    else {
        Write-Host 'Install-image for ''Core'' already present.'
    }
}
else {
    Write-Host 'No install-image found for ''Core''...'
}

$guiImageFile = Get-ChildItem (Join-Path -Path $PSScriptRoot -ChildPath '\Images') -Filter '*_GUI_*' | Sort-Object Name | Select-Object -Last 1
if ($guiImageFile) {
    $guiImageName = [System.IO.Path]::GetFileNameWithoutExtension(($guiImageFile.FullName))
    if (-not (Get-WdsInstallImage -ImageName $guiImageName -ImageGroup $wimImageGroupName -ErrorAction SilentlyContinue)) {
        Write-Host 'Importing ''GUI'' install-image '$($guiImageFile.FullName)'...'
        if ($unattendFiles.GuiEdition) {
            $unattendFilePath = (Get-ChildItem -Path $unattendDestinationPath | Where-Object { $_.Name -eq $unattendFiles.GuiEdition }).FullName
            Write-Host ' with unattend-file '$unattendFilePath'...'
            Import-WdsInstallImage -Path $guiImageFile.FullName -ImageGroup $wimImageGroupName -UnattendFile $unattendFilePath | Out-Null
        }
        else {
            Import-WdsInstallImage -Path $guiImageFile.FullName -ImageGroup $wimImageGroupName | Out-Null
        }
    }
    else {
        Write-Host 'Install-image for ''GUI'' already present.'
    }
}
else {
    Write-Host 'No install-image found for ''GUI''...'
}
#endregion
#######################################

#######################################
#region clients
#######################################

foreach ($machine in $environmentConfiguration.Nodes) {
    if ($machine.Name -ne $env:COMPUTERNAME) {
        $unattendFilePath = $null
        if ($machine.AllProperties.UnattendFileName) {
            $unattendFilePath = (Get-ChildItem -Path $unattendDestinationPath | Where-Object { $_.Name -eq $machine.AllProperties.UnattendFileName }).FullName
            $unattendFilePath = $unattendFilePath.Substring("\$($wdsRemoteInstallPath.TrimEnd('\'))".Length)
        }

        $networkAdapter = $machine.NetworkAdapters | Where-Object { $_.StaticMacAddress } | Select-Object -First 1
        if ($networkAdapter) {
            $client = Get-WdsClient -DeviceName $machine.Name
            $parameters = @{
                DeviceName        = $machine.Name
                DeviceID          = $networkAdapter.StaticMacAddress
                PxePromptPolicy   = 'NoPrompt'
                BootImagePath     = $bootImagePath
            }
            if ($unattendFilePath) {
                $parameters.WdsClientUnattend = $unattendFilePath
            }

            if (-not $client) {
                Write-Host ("Registering client {0,-8} [$($networkAdapter.StaticMacAddress)] ($([System.IO.Path]::GetFileName($unattendFilePath)))..." -f $($machine.Name))
                $null = New-WdsClient @parameters
            }
            else {
                Write-Host ("Updating client    {0,-8} [$($networkAdapter.StaticMacAddress)] ($([System.IO.Path]::GetFileName($unattendFilePath)))..." -f $($machine.Name))
                $null = Set-WdsClient @parameters
            }
        }
    }
}

#endregion
#######################################

Write-Host 'Finished.'
