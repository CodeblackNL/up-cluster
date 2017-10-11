#
# bTfsServerSetup: DSC resource to install Team Foundation Server.

function Get-TargetResource {
    [OutputType([Hashtable])]
    param (	
        [parameter(Mandatory)] 
        [string] $Name
    )

    $product = Get-TfsProduct
    if ($product) {
        $ensureConfiguration = "Absent"
        $regPath = (Get-ChildItem -Path HKLM:\SOFTWARE\Microsoft\TeamFoundationServer | Sort Name | Select -Last 1).PSPath
		$components = Get-ChildItem -Path "$regPath\InstalledComponents" -ErrorAction SilentlyContinue `
            | Where-Object { (Get-ItemProperty -Path $_.PSPath -Name IsConfigured -ErrorAction SilentlyContinue).IsConfigured -eq 1} `
            | ForEach-Object { Split-Path -Path $_.PSPath -Leaf }
        if ($components -ne $null) {
		    if ($components.Contains("ApplicationTier")) {
                $ensureConfiguration = "Present"
		    }
        }

        $returnValue = @{
            Name = $env:COMPUTERNAME
            EnsureBinaries = "Present"
            EnsureConfiguration = $ensureConfiguration
        }
    }
    else {
        $returnValue = @{
            Name = $env:COMPUTERNAME
            EnsureBinaries = "Absent"
            EnsureConfiguration = "Absent"
        }
    }

    if ($returnValue.EnsureBinaries -eq "Present" -and $returnValue.EnsureConfiguration -eq "Present") {
        Write-Verbose "TFS is installed and configured"
    }
    elseif ($returnValue.EnsureBinaries -eq "Present") {
        Write-Verbose "TFS is installed but not configured"
    }
    else {
        Write-Verbose "TFS is not installed"
    }

	return $returnValue
}

function Test-TargetResource {
    [OutputType([Boolean])]
    param (	
        [parameter(Mandatory)] 
        [string] $Name,

        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = "Present",

        [uint16]
        $WebSitePort = 80,

        [System.String]
        $WebSiteVirtualDirectoryName = '',

        [System.String]
        $SqlServerInstance = "$($env:COMPUTERNAME)",

        [System.String]
        $FileCacheDirectory = "C:\Program Files\Microsoft Team Foundation Server 12.0\Application Tier\Web Services\_tfs_data",

        [ValidateNotNullOrEmpty()]
        [System.String]
        $TeamProjectCollectionName = "DefaultCollection",

        [PSCredential]
        $TfsServiceAccount,

        [System.String]
        $TfsServiceAccountUserName = "NT AUTHORITY\Network Service",
        
        [PSCredential]
        $ReportReaderAccount,

        [System.String]
        $ReportReaderAccountUserName,
        
        [ValidateNotNull()]
        [PSCredential]
		$TfsAdminCredential,

        [bool]$SendFeedback = $false,

        [string]
		$LogPath,
        
        [ValidateNotNullOrEmpty()]
        [string]
		$SourcePath,

        [System.Management.Automation.PSCredential]
        $SourceCredential
    )

    $info = Get-TargetResource -Name $Name
    
    return ($info.Name -eq $Name -and $info.EnsureBinaries -eq $Ensure -and $info.EnsureConfiguration -eq $Ensure)
}

function Set-TargetResource {
    param (	
        [parameter(Mandatory)] 
        [string] $Name,

        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = "Present",

        [uint16]
        $WebSitePort = 80,

        [System.String]
        $WebSiteVirtualDirectoryName = '',

        [System.String]
        $SqlServerInstance = "$($env:COMPUTERNAME)",

        [System.String]
        $FileCacheDirectory = "C:\Program Files\Microsoft Team Foundation Server 12.0\Application Tier\Web Services\_tfs_data",

        [ValidateNotNullOrEmpty()]
        [System.String]
        $TeamProjectCollectionName = "DefaultCollection",

        [PSCredential]
        $TfsServiceAccount,

        [System.String]
        $TfsServiceAccountUserName = "NT AUTHORITY\Network Service",
        
        [PSCredential]
        $ReportReaderAccount,

        [System.String]
        $ReportReaderAccountUserName,
        
        [ValidateNotNull()]
        [PSCredential]
		$TfsAdminCredential,

        [bool]$SendFeedback = $false,

        [string]
		$LogPath,
        
        [ValidateNotNullOrEmpty()]
        [string]
		$SourcePath,

        [System.Management.Automation.PSCredential]
        $SourceCredential
    )

    if ($Ensure -ne "Present") {
        $product = Get-TfsProduct
        if ($product -ne $null) {
            Write-Verbose "Uninstalling TFS"
            $product.Uninstall()
        }
    }
    else {
    	if ([string]::IsNullOrEmpty($LogPath)) {
            $LogPath = Join-Path $env:SystemDrive -ChildPath "Logs"
    	}
    
        if (!(Test-Path $LogPath)) {
            New-Item $LogPath -ItemType Directory
        }
    
        $info = Get-TargetResource -Name $Name

        if ($info.EnsureBinaries -eq "Absent") {
            Install-TfsBinaries -SourcePath $SourcePath -SourceCredential $SourceCredential -LogPath $LogPath
        }

        if ($info.EnsureConfiguration -eq "Absent") {
            Configure-Tfs -LogPath $LogPath -TfsAdminCredential $TfsAdminCredential `
                          -SendFeedback $SendFeedback `
			              -WebSitePort $WebSitePort -WebSiteVirtualDirectoryName $WebSiteVirtualDirectoryName `
			              -SqlServerInstance $SqlServerInstance -TeamProjectCollectionName $TeamProjectCollectionName `
                          -FileCacheDirectory $FileCacheDirectory `
			              -TfsServiceAccount $TfsServiceAccount -TfsServiceAccountUserName $TfsServiceAccountUserName `
	                      -ReportReaderAccount $ReportReaderAccount -ReportReaderAccountUserName $ReportReaderAccountUserName
        }
    }
}


function Get-TfsProduct {
    return Get-WmiObject Win32_Product -Filter "Name LIKE 'Microsoft Team Foundation Server %'"
}

function NetUse {
    param (   
        [parameter(Mandatory)]
        [string]
        $SourcePath,
        
        [parameter(Mandatory)]
        [PSCredential]
        $Credential,
        
        [string]
        [ValidateSet("Present","Absent")]
        $Ensure = "Present"
    )

    if(($SourcePath.Length -ge 2) -and ($SourcePath.Substring(0,2) -eq "\\"))
    {
        $argumentList = @()
        if ($Ensure -eq "Absent")
        {
            $argumentList += "use", $SourcePath, "/del"
        }
        else 
        {
            $argumentList += "use", $SourcePath, $($Credential.GetNetworkCredential().Password), "/user:$($Credential.GetNetworkCredential().Domain)\$($Credential.GetNetworkCredential().UserName)"
        }

        &"net" $argumentList
    }
}

function Install-TfsBinaries {
    param (
        [string] $SourcePath,
        [PSCredential] $SourceCredential,
        [string] $LogPath
    )

    Write-Verbose "Installing TFS from '$SourcePath' using '$($SourceCredential.UserName)'"

    try {
        if ($SourceCredential) {
            NetUse -SourcePath $SourcePath -Credential $SourceCredential -Ensure 'Present'
        }

        $exeFiles = @(Get-ChildItem -Path $SourcePath -Filter '*.exe')
        if ($exeFiles.Length -eq 1) {
            $setupFileName = $exeFiles.Name
        }
        else {
            $setupFileName = 'tfs_server.exe'
        }
        $setupCommand = Join-Path -Path $SourcePath -ChildPath $setupFileName
        Write-Verbose "Path: $SourcePath"
        $setupCommand += " /Full /Silent /NoWeb /NoRefresh"

	    if ($LogPath) {
	        $logFilePath = Join-Path $LogPath -ChildPath "tfs-log.txt"
	        $setupCommand += " > $logFilePath 2>&1 "
	    }

        Write-Host "Start installation of TFS 2015 ($setupCommand)"
        Invoke-Expression $setupCommand

        $processName = [System.IO.Path]::GetFileNameWithoutExtension($setupFileName)
        Write-Host "Waiting for installation of TFS to finish ($processName)"
        do {
            Start-Sleep -Seconds 5
            $process = Get-Process -Name $processName -ErrorAction:SilentlyContinue
            if ($process) {
                Write-Debug "- process still running..."
            }
        }
        until ($process -eq $null)

        $setupResult = Get-TargetResource -Name $Name
        if ($setupResult.EnsureBinaries -ne "Present") {
            throw "TFS installation failed"
        }

        Write-Host "Finished installation of Team Foundation Server"
    }
    finally {
        if ($SourceCredential) {
            NetUse -SourcePath $SourcePath -Credential $SourceCredential -Ensure 'Absent'
        }
    }

    <#if ($SourceCredential) {
        $sourceFolder = Split-Path $SourcePath -Leaf
        $targetFolder = Join-Path -Path ([IO.Path]::GetTempPath()) -ChildPath $sourceFolder
        NetUse -SourcePath $SourcePath -Credential $SourceCredential -Ensure "Present"
        Write-Verbose "Copying from: $SourcePath"
        Write-Verbose "Copying to: $targetFolder"
        & robocopy.exe ($SourcePath) ($targetFolder) /e
        $SourcePath = $targetFolder
        NetUse -SourcePath $SourcePath -Credential $SourceCredential -Ensure "Absent"
    }

    $cmd = Join-Path $SourcePath -ChildPath "tfs_server.exe"
    Write-Verbose "Path: $SourcePath"
    $cmd += " /Full /Silent /NoWeb /NoRefresh"

	if ($LogPath) {
	    $logFile = Join-Path $LogPath -ChildPath "tfsApplicationTierInstall-log.txt"
	    $cmd += " > $logFile 2>&1 "
	}

    try {
        Write-Debug "Installing TFS with the following command: $cmd"
        Invoke-Expression $cmd
        do {
            Write-Debug "Checking process still running"
            Start-Sleep -Seconds 5
            $process = Get-Process -Name tfs_server -ErrorAction:SilentlyContinue
        }
        until ($process -eq $null)

        $setupResult = Get-TargetResource -Name $Name
        if ($setupResult.EnsureBinaries -ne "Present") {
            throw "TFS installation failed with result code: $setupResult"
        }
    }
    finally {
        if ($SourceCredential -and $targetFolder -and (Test-Path -Path $targetFolder -PathType Container)) {
            Remove-Item -Path $targetFolder -Recurse -Force
        }
    }#>
}

function Configure-Tfs {
    param (
        [string] $LogPath,
        [PSCredential] $TfsAdminCredential,
        [bool]$SendFeedback,
        [uint16]$WebSitePort,
        [string]$WebSiteVirtualDirectoryName,
        [string]$SqlServerInstance,
        [string]$TeamProjectCollectionName,
        [string]$FileCacheDirectory,
        [PSCredential]$TfsServiceAccount,
        [string]$TfsServiceAccountUserName,
        [PSCredential]$ReportReaderAccount,
        [string]$ReportReaderAccountUserName

		# TODO: add parameters for
	    #       - UseWss/ConfigureWss (default $false)
	    #       - UrlHostNameAlias
	    #       - ReportServerUrl (default 'http://$($hostName):80/ReportServer')
	    #       - ReportManagerUrl (default 'http://$($hostName):80/Reports')
    )

	if (-not $LogPath) {
        $LogPath = [IO.Path]::GetTempPath()
	}

    $logOutFile = Join-Path $LogPath -ChildPath "TfsServerConfigure-log.txt"
	Remove-Item $logOutFile -ErrorAction:SilentlyContinue

    $regPath = (Get-ChildItem -Path HKLM:\SOFTWARE\Microsoft\TeamFoundationServer | Sort Name | Select -Last 1).PSPath
    $configExePath = Join-Path (Get-ItemProperty -Path $regPath -Name InstallPath).InstallPath -ChildPath "\tools\tfsconfig.exe"
	#$configFilePath = [System.IO.Path]::GetTempFileName()
	$configFilePath = Join-Path $LogPath -ChildPath "config_server.ini"

	$hostName = $env:COMPUTERNAME

	# create the config-file
	Write-Debug "Generating TFS Server 2013.4 configuration-file"
	$unattendCommand  = "& '$configExePath'"
	$unattendCommand += " unattend /create /type:standard"
	$unattendCommand += " /unattendfile:$configFilePath"
	$unattendCommand += " /inputs:'"
	$unattendCommand += "SendFeedback=$SendFeedback"
	$unattendCommand += ";WebSiteVDirName=$WebSiteVirtualDirectoryName"
	$unattendCommand += ";SiteBindings=http:*:$($WebSitePort):"
	$unattendCommand += ";PublicUrl=http://$($env:COMPUTERNAME):$($WebSitePort)/$WebSiteVirtualDirectoryName"
	$unattendCommand += ";UseWss=False"
	$unattendCommand += ";UrlHostNameAlias=tfs"
	$unattendCommand += ";SqlInstance=$SqlServerInstance"
	$unattendCommand += ";UseReporting=True"
	$unattendCommand += ";ReportingServicesInstance=$SqlServerInstance"
	$unattendCommand += ";ReportServerUrl=http://$($hostName):80/ReportServer"
	$unattendCommand += ";ReportManagerUrl=http://$($hostName):80/Reports"
	$unattendCommand += ";AnalysisInstance=$SqlServerInstance"
	if ($TeamProjectCollectionName) {
	    $unattendCommand += ";CollectionName=$TeamProjectCollectionName"
	}

    if ($TfsServiceAccount) {
        $TfsServiceAccountUserName = $TfsServiceAccount.UserName
    }
    if ($TfsServiceAccountUserName) {
        $isServiceAccountBuiltIn = $TfsServiceAccountUserName.ToUpperInvariant().Contains('NT AUTHORITY')
	    $unattendCommand += ";IsServiceAccountBuiltIn=$isServiceAccountBuiltIn;ServiceAccountName=$TfsServiceAccountUserName"
    }

    if ($ReportReaderAccount) {
        $ReportReaderAccountUserName = $ReportReaderAccount.UserName
    }
	if ($ReportReaderAccountUserName) {
		$unattendCommand += ";ReportReaderSameAccount=False;ReportReaderAccountName=$ReportReaderAccountUserName"
	}
	else {
		$unattendCommand += ";ReportReaderSameAccount=True"
	}

	$unattendCommand += "'"

    Write-Verbose "Creating TFS configuration-file with the following command: '$unattendCommand'"
	Invoke-Expression $unattendCommand

	Write-Debug "Modifying TFS configuration-file"
	$configContent = Get-Content -Path $configFilePath
	if ($TfsServiceAccount) {
		$configContent = $configContent.Replace("ServiceAccountPassword=","ServiceAccountPassword=$($TfsServiceAccount.GetNetworkCredential().Password)")
	}
	if ($ReportReaderAccount) {
		$configContent = $configContent.Replace("ReportReaderAccountPassword=","ReportReaderAccountPassword=$($ReportReaderAccount.GetNetworkCredential().Password)")
	}
	Set-Content -Path $configFilePath -Value $configContent

	# configure using the config-file
	Write-Debug "Configuring TFS"
	$configCommand  = "& '$configExePath'"
	$configCommand += " unattend /configure"
	$configCommand += " /unattendfile:$configFilePath"
	$configCommand += " /continue"

    Write-Verbose "Configuring TFS with the following command: '$configCommand'"

    Invoke-Expression $configCommand | Out-File $logOutFile
#	Invoke-Command -ComputerName $env:COMPUTERNAME -Credential $TfsAdminCredential -ScriptBlock {
#		param ($configCommand, $logOutFile)
#	
#        Invoke-Expression $configCommand | Out-File $logOutFile
#	} -ArgumentList $configCommand, $logOutFile

	if ($logOutFile -and (Test-Path $logOutFile)) {
		$logText = (Get-Content $logOutFile) -join ""
		if (![string]::IsNullOrEmpty($logText)) {
			if ($logText.Contains("[Error]")) {
				throw "Configuration failed: $logText"
			}
		}
	}
}

Export-ModuleMember -Function *-TargetResource
