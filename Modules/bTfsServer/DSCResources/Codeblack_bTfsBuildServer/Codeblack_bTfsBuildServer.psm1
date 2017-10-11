#
# bTfsBuildServer: DSC resource to install Team Foundation Server Build Server.
#


#
# The Get-TargetResource cmdlet.
#
function Get-TargetResource
{
    [OutputType([Hashtable])]
    param
    (	
        [parameter(Mandatory)] 
        [string] $Name
    )

    $product = Get-TfsProduct

    if ($product -ne $null)
    {
        $ensureConfiguration = "Absent"
		$components = Get-ChildItem -Path HKLM:\SOFTWARE\Microsoft\TeamFoundationServer\12.0\InstalledComponents -ErrorAction SilentlyContinue | where { (Get-ItemProperty -Path $_.PSPath -Name IsConfigured -ErrorAction SilentlyContinue).IsConfigured -eq 1} | foreach { Split-Path -Path $_.PSPath -Leaf }
        if ($components -ne $null)
        {
		    if ($components.Contains("TeamBuild"))
			{
                $ensureConfiguration = "Present"
		    }
        }

        $returnValue = @{
            Name = $env:COMPUTERNAME
            EnsureBinaries = "Present"
            EnsureConfiguration = $ensureConfiguration
        }
    }
    else
    {
        $returnValue = @{
            Name = $env:COMPUTERNAME
            EnsureBinaries = "Absent"
            EnsureConfiguration = "Absent"
        }
    }

    if ($returnValue.EnsureBinaries -eq "Present" -and $returnValue.EnsureConfiguration -eq "Present")
    {
        Write-Verbose "TFS is installed and the build controller is configured"
    }
    elseif ($returnValue.EnsureBinaries -eq "Present"
    )
    {
        Write-Verbose "TFS is installed but the build controller is not configured"
    }
    else
    {
        Write-Verbose "TFS is not installed"
    }

	$returnValue
}


#
# The Set-TargetResource cmdlet.
#
function Set-TargetResource
{
    param
    (	
        [parameter(Mandatory)] 
        [string] $Name,

        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = "Present",

        [PSCredential] $BuildServiceAccount,

        [string] $BuildServiceAccountUserName,

        [ValidateNotNullOrEmpty()]
        [System.String]
        $TeamProjectCollectionUri,
        
        [uint16]
        $Port = 9191,

        [uint16]
        $AgentCount = 2,

        [string] $LogPath,
        
        [ValidateNotNullOrEmpty()]
        [string] $SourcePath,

        [PSCredential] $SetupCredential
    )

    if ($Ensure -ne "Present")
    {
        $product = Get-TfsProduct
        if ($product -ne $null)
        {
            Write-Verbose "Uninstalling TFS"
            $product.Uninstall()
        }
    }
    else
    {
    	if ([string]::IsNullOrEmpty($LogPath))
    	{
            $LogPath = Join-Path $env:SystemDrive -ChildPath "Logs"
    	}
    
        if (!(Test-Path $LogPath))
        {
            New-Item $LogPath -ItemType Directory
        }
    
        $info = Get-TargetResource -Name $Name

        if ($info.EnsureBinaries -eq "Absent")
        {
            Install-TfsBinaries -LogPath $LogPath -SourcePath $SourcePath -SourcePathCredential $SetupCredential
        }

        if ($info.EnsureConfiguration -eq "Absent")
        {
            Configure-Tfs -LogPath $LogPath -SetupCredential $SetupCredential `
			              -TeamProjectCollectionUri $TeamProjectCollectionUri -Port $Port -AgentCount $AgentCount `
			              -BuildServiceAccount $BuildServiceAccount -BuildServiceAccountUserName $BuildServiceAccountUserName
        }
    }
}

#
# The Test-TargetResource cmdlet.
#
function Test-TargetResource
{
    [OutputType([Boolean])]
    param
    (	
        [parameter(Mandatory)] 
        [string] $Name,
        
        [ValidateSet("Present", "Absent")]
        [System.String]
        $Ensure = "Present",

        [PSCredential] $BuildServiceAccount,

        [string] $BuildServiceAccountUserName,

        [ValidateNotNullOrEmpty()]
        [System.String]
        $TeamProjectCollectionUri,
        
        [uint16]
        $Port = 9191,

        [uint16]
        $AgentCount = 2,

        [string] $LogPath,

        [ValidateNotNullOrEmpty()]
        [string] $SourcePath,

        [PSCredential] $SetupCredential
    )

    $info = Get-TargetResource -Name $Name
    
    return ($info.Name -eq $Name -and $info.EnsureBinaries -eq $Ensure -and $info.EnsureConfiguration -eq $Ensure)
}



function NetUse
{
    param
    (	   
        [parameter(Mandatory)] 
        [string] $SharePath,
        
        [PSCredential]$SharePathCredential,
        
        [string] $Ensure = "Present"
    )

    if ($null -eq $SharePathCredential)
    {
        return;
    }

	$smbPath = $SharePath.Split("\")[0..3] -join "\"
    if ($Ensure -eq "Absent")
    {
        Write-Verbose -Message "Disconnecting from share $smbPath ..."
        Remove-SmbMapping -RemotePath $smbPath
    }
    else 
    {
        Write-Verbose -Message "Connecting to share $smbPath ..."
        $cred = $SharePathCredential.GetNetworkCredential()
        $pwd = $cred.Password 
        $user = $cred.Domain + "\" + $cred.UserName
		New-SmbMapping -RemotePath $smbPath -UserName $user -Password $pwd
    }
}

function Get-TfsProduct
{
    $product = Get-WmiObject Win32_Product -Filter "Name LIKE 'Microsoft Team Foundation Server 201%'"
    return $product
}

function Install-TfsBinaries
{
    param
    (
        [string] $LogPath,
        [string] $SourcePath,
        [PSCredential] $SourcePathCredential
    )

    $cmd = Join-Path $SourcePath -ChildPath "tfs_server.exe"
    $cmd += " /install /quiet "

	if ($LogPath)
	{
	    $logFile = Join-Path $LogPath -ChildPath "tfsApplicationTierInstall-log.txt"
	    $cmd += " > $logFile 2>&1 "
	}

    NetUse -SharePath $SourcePath -SharePathCredential $SourcePathCredential -Ensure "Present"
    try
    {
        Write-Debug "Installing TFS with the following command: $cmd"
        Invoke-Expression $cmd
        do
        {
            Write-Debug "Checking process still running"
            Start-Sleep -Seconds 5
            $process = Get-Process -Name tfs_server -ErrorAction:SilentlyContinue
        }
        until ($process -eq $null)
        $setupResult = Get-TargetResource -Name $Name
        if ($setupResult.EnsureBinaries -ne "Present")
        {
            throw "TFS installation failed with result code: $setupResult"
        }
    }
    finally
    {
        NetUse -SharePath $SourcePath -SharePathCredential $SourcePathCredential -Ensure "Absent"
    }
}

function Configure-Tfs
{
    param
    (
        [string] $LogPath,
        [PSCredential] $SetupCredential,
        [string] $TeamProjectCollectionUri,
        [uint16] $Port,
        [uint16] $AgentCount,
        [PSCredential] $BuildServiceAccount,
        [string] $BuildServiceAccountUserName
    )

	$logOutFile = Join-Path $LogPath -ChildPath "TfsServerConfigure-log.txt"
	Remove-Item $logOutFile -ErrorAction:SilentlyContinue

    $configExePath = Join-Path (Get-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\TeamFoundationServer\12.0 -Name InstallPath).InstallPath -ChildPath "\tools\tfsconfig.exe"
	#$configFilePath = [System.IO.Path]::GetTempFileName()
	$configFilePath = Join-Path $LogPath -ChildPath "config_build.ini"

	$hostName = $env:COMPUTERNAME

	# create the config-file
	Write-Debug "Generating TFS 2013.4 Build-server configuration-file"
	$unattendCommand  = "& '$configExePath'"
	$unattendCommand += " unattend /create /type:build"
	$unattendCommand += " /unattendfile:$configFilePath"
	$unattendCommand += " /inputs:'"
	$unattendCommand += "SendFeedback=False"
	$unattendCommand += ";ConfigurationType=create"
	$unattendCommand += ";AgentCount=$AgentCount"
	$unattendCommand += ";Port=$Port"
	$unattendCommand += ";CollectionUrl=$TeamProjectCollectionUri"
	$unattendCommand += ";NewControllerName=$hostName-Controller"
	if ($BuildServiceAccount)
	{
		$unattendCommand += ";IsServiceAccountBuiltIn=False;ServiceAccountName=$($BuildServiceAccount.UserName)"
	}
	elseif ($BuildServiceAccountUserName)
	{
		$unattendCommand += ";IsServiceAccountBuiltIn=True;ServiceAccountName=$BuildServiceAccountUserName"
	}
	else
	{
		$unattendCommand += ";IsServiceAccountBuiltIn=True;ServiceAccountName=NT Authority\Network Service"
	}
	$unattendCommand += "'"

    Write-Debug "Creating TFS configuration-file with the following command: '$unattendCommand'"
	Invoke-Expression $unattendCommand

	Write-Debug "Modifying TFS configuration-file"
	$configContent = Get-Content -Path $configFilePath
	if ($BuildServiceAccount)
	{
		$password = $BuildServiceAccount.GetNetworkCredential().Password
		$configContent = $configContent.Replace("ServiceAccountPassword=","ServiceAccountPassword=$password")
	}
	Set-Content -Path $configFilePath -Value $configContent

	# configure using the config-file
	Write-Debug "Configuring TFS 2013.4 Build-server"
	$configCommand  = "& '$configExePath'"
	$configCommand += " unattend /configure"
	$configCommand += " /unattendfile:$configFilePath"
	$configCommand += " /continue"

    Write-Debug "Configuring TFS with the following command: '$configCommand'"
    Invoke-Expression $configCommand | Out-File $logOutFile

	#Invoke-Command -ComputerName $env:COMPUTERNAME -Credential $SetupCredential -ScriptBlock {
	#	param ($configCommand, $logOutFile)
	#
    #    Invoke-Expression $configCommand | Out-File $logOutFile
	#} -ArgumentList $configCommand, $logOutFile

	if ($logOutFile -and (Test-Path $logOutFile))
	{
		$logText = (Get-Content $logOutFile) -join ""
		if (![string]::IsNullOrEmpty($logText))
		{
			if ($logText.Contains("[Error]"))
			{
				throw "Configuration failed: $logText"
			}
		}
	}
}

Export-ModuleMember -Function *-TargetResource
