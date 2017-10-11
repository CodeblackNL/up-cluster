#
# bTfsAgentSetup: DSC resource to install Team Foundation Server Agent.

function Get-TargetResource {
    [OutputType([Hashtable])]
    param (	
        [parameter(Mandatory = $true)]
        [string]$AgentName,
        [parameter(Mandatory = $true)]
        [string]$ServerUrl,
        [parameter(Mandatory = $true)]
        [PSCredential]$AgentCredential
    )

    # TODO: validate agent-name (whitespaces, etc.)

    $ensure = 'Absent'
    
    $serviceName = "vsoagent.$((New-Object -TypeName System.Uri -ArgumentList $ServerUrl).Host).$AgentName"
	Write-Verbose "Locating agent using service '$serviceName'."
    if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
        $servicePath = ((Get-WmiObject -Class Win32_Service -Filter "Name='$serviceName'").PathName -split ' ' | Select-Object -First 1).Trim('"')
	    Write-Verbose "Found agent-service at '$servicePath'"
        if ($servicePath -and (Test-Path -Path $servicePath)) {
	        Write-Verbose "Found agent-folder at '$servicePath'"
            $agentFolder = Split-Path -Path $servicePath.TrimEnd('vsoAgentService.exe')
	        Write-Verbose "Found agent-folder at '$agentFolder'"
            $ensure = 'Present'

            $settingsFilePath = Join-Path -Path $agentFolder -ChildPath 'settings.json'
            if (Test-Path -Path $settingsFilePath) {
	            Write-Verbose "Found settings-file at '$settingsFilePath'"
                $settings = Get-Content -Path $settingsFilePath | ConvertFrom-Json

                $settingsAgentName = $settings.AgentName
                $settingsServerUrl = $settings.ServerUrl
                $settingsWorkFolder = $settings.WorkFolder
                $settingsPoolName = $settings.PoolName
                $settingsRunAsWindowsService = $settings.RunAsWindowsService
                $settingsWindowsServiceName = $settings.WindowsServiceName

                $service = Get-WmiObject -Class Win32_Service -Filter "Name='$serviceName'"
                if ($service) {
                    $agentUserName = $service.StartName
                }
            }
            else {
	            Write-Verbose "Agent-settings-file '$settingsFilePath' not found."
            }
        }
        else {
	        Write-Verbose "Agent-location '$servicePath' not found."
        }
    }
    else {
	    Write-Verbose "Agent-service '$serviceName' not found."
    }

    return @{
        AgentName = $AgentName
        Ensure = $ensure
        ServerUrl = $settingsServerUrl
        AgentFolder = $agentFolder
        WorkFolder = $settingsWorkFolder
        PoolName = $settingsPoolName
        RunAsWindowsService = $settingsRunAsWindowsService
        WindowsServiceName = $settingsWindowsServiceName
        AgentCredentialUserName = $agentUserName
    }
}

function Test-TargetResource {
    [OutputType([Boolean])]
    param (
        [parameter(Mandatory)]
        [string]$AgentName,
        [ValidateSet('Present', 'Absent')]
        [System.String]$Ensure = 'Present',
        [parameter(Mandatory)]
        [string]$ServerUrl,
        [string]$AgentFolder = 'C:\Agent',
        [parameter(Mandatory = $true)]
        [PSCredential]$AgentCredential,
        [string]$WorkFolder = (Join-Path -Path $AgentFolder -ChildPath '_work'),
        [string]$PoolName = 'default',
        [bool]$RunAsWindowsService = $true
    )

	Write-Verbose "Resource-version: '$version'."

    $info = Get-TargetResource -AgentName $AgentName -ServerUrl $ServerUrl -AgentCredential $AgentCredential

	Write-Verbose "AgentName:           '$AgentName' ($($info.AgentName))"
	Write-Verbose "Ensure:              '$Ensure' ($($info.Ensure))"
	Write-Verbose "ServerUrl:           '$ServerUrl' ($($info.ServerUrl))"
	Write-Verbose "AgentFolder:         '$AgentFolder' ($($info.AgentFolder))"
	Write-Verbose "AgentCredential:     '$($AgentCredential.UserName)' ($($info.AgentCredentialUserName))"
	Write-Verbose "WorkFolder:          '$WorkFolder' ($($info.WorkFolder))"
	Write-Verbose "PoolName:            '$PoolName' ($($info.PoolName))"
	Write-Verbose "RunAsWindowsService: '$RunAsWindowsService' ($($info.RunAsWindowsService))"
    
    $diff = @()

    if (-not $info) {
        return $false
    }

    if ($info.AgentName -ne $AgentName) {
        $diff += 'AgentName'
    }
    if ($info.Ensure -ne $Ensure) {
        $diff += 'Ensure'
    }
    if ($info.ServerUrl -ne $ServerUrl) {
        $diff += 'ServerUrl'
    }
    if ($info.AgentFolder -ne $AgentFolder) {
        $diff += 'AgentFolder'
    }
    if ($info.WorkFolder -ne $WorkFolder) {
        $diff += 'WorkFolder'
    }
    if ($info.PoolName -ne $PoolName) {
        $diff += 'PoolName'
    }
    if ($info.RunAsWindowsService -ne $RunAsWindowsService) {
        $diff += 'RunAsWindowsService'
    }
    if ($RunAsWindowsService -and $info.AgentCredentialUserName -ne $AgentCredential.UserName) {
        $diff += 'AgentCredential'
    }

    if ($diff) {
		Write-Verbose "Differences found: '$diff'."
        return $false
    }
    else {
		Write-Verbose "No differences found."
        return $true
    }
}

function Set-TargetResource {
    param (
        [parameter(Mandatory)]
        [string]$AgentName,
        [ValidateSet('Present', 'Absent')]
        [System.String]$Ensure = 'Present',
        [parameter(Mandatory)]
        [string]$ServerUrl,
        [string]$AgentFolder = 'C:\Agent',
        [parameter(Mandatory = $true)]
        [PSCredential]$AgentCredential,
        [string]$WorkFolder = (Join-Path -Path $AgentFolder -ChildPath '_work'),
        [string]$PoolName = 'default',
        [bool]$RunAsWindowsService = $true
    )

    $info = Get-TargetResource -AgentName $AgentName -ServerUrl $ServerUrl -AgentCredential $AgentCredential
    
    if ($Ensure -eq 'Absent' -and $Ensure -ne $info.Ensure) {
        Uninstall-TfsAgent -AgentFolder $AgentFolder -WorkFolder $WorkFolder -AgentCredential $AgentCredential
    }

    if ($Ensure -eq 'Present' -and $Ensure -ne $info.Ensure) {
        Install-TfsAgent `
            -AgentName $AgentName `
            -ServerUrl $ServerUrl `
            -AgentFolder $AgentFolder `
            -AgentCredential $AgentCredential `
            -WorkFolder $WorkFolder `
            -PoolName $PoolName `
            -RunAsWindowsService $RunAsWindowsService
    }
}

function Uninstall-TfsAgent {
    param (
        [string]$AgentFolder,
        [string]$WorkFolder,
        [PSCredential]$AgentCredential
    )

    try {
    	Write-Verbose "Uninstalling..."
    
        # unconfigure
        if (Test-Path -Path $AgentFolder -PathType Container) {
		    $unconfigureParameters = @("/Unconfigure", "/NoPrompt")
            $agentFilePath = "$(Join-Path -Path $AgentFolder -ChildPath 'Agent\VsoAgent.exe')"
		    Write-Verbose "Unconfiguring agent: $agentFilePath $unconfigureParameters"
		    Invoke-Command -ScriptBlock { & "$using:agentFilePath" $using:unconfigureParameters } -ComputerName localhost -Authentication CredSSP -Credential $AgentCredential
        }

        # remove working-folder
        if (Test-Path -Path $WorkFolder -PathType Container) {
            Remove-Item $WorkFolder -Recurse -Force
        }

        # remove agent-folder
        if (Test-Path $AgentFolder -PathType Container) {
            Remove-Item $AgentFolder -Recurse -Force
        }

	    Write-Verbose "Uninstall of agent '$AgentName' finished."
    }
    catch {
        Write-Error $_
    }
}

function Install-TfsAgent {
    param (
        [string]$AgentName,
        [string]$ServerUrl,
        [string]$AgentFolder,
        [PSCredential]$AgentCredential,
        [string]$WorkFolder,
        [string]$PoolName,
        [bool]$RunAsWindowsService
    )

    try {
		if (-not (Test-Path $AgentFolder)) {
	        Write-Verbose "Agent-folder '$AgentFolder' does not exist; installing..."
			$force = $false

            # download agent-zip from TFS-instance
            $downloadPath = [System.IO.Path]::GetTempFileName()
            $url = "$($ServerUrl.TrimEnd('/'))/_apis/distributedtask/packages/agent"
		    Write-Verbose "Downloading from '$url'."
		    Write-Verbose "Downloading to '$downloadPath'."

            Write-Verbose "Downloading using credential '$($AgentCredential.UserName)'."
            Invoke-WebRequest -Uri $url -OutFile $downloadPath -Credential $AgentCredential

            # unzip the agent-zip
		    Write-Verbose "Unzipping to '$AgentFolder'."
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            if (Test-Path $AgentFolder -PathType Container) {
                Remove-Item $AgentFolder -Recurse -Force
            }
            [System.IO.Compression.ZipFile]::ExtractToDirectory($downloadPath, $AgentFolder)
        }
        else {
			Write-Verbose "Agent-folder '$AgentFolder' already exists; reconfiguring..."
			$force = $true
        }

		$configureParameters = @("/Configure", "/NoPrompt", "/ServerUrl:$ServerUrl", "/Name:$AgentName", "/PoolName:$PoolName", "/WorkFolder:$WorkFolder")
        if ($RunAsWindowsService) {
            $configureParameters += '/RunningAsService'
            $configureParameters += "/WindowsServiceLogonAccount:$($AgentCredential.UserName)"
            $configureParameters += "/WindowsServiceLogonPassword:$($AgentCredential.GetNetworkCredential().Password)"
        }
        if ($force) {
            $configureParameters += '/Force'
        }

		# Run the configuration
        $agentFilePath = "$(Join-Path -Path $AgentFolder -ChildPath 'Agent\VsoAgent.exe')"
		Write-Verbose "Configuring agent: $agentFilePath $configureParameters"
		Invoke-Command -ScriptBlock { & "$using:agentFilePath" $using:configureParameters } -ComputerName localhost -Authentication CredSSP -Credential $AgentCredential

		Write-Verbose "Install of agent '$AgentName' finished."
    }
    finally {
        # clean up (delete downloaded agent-zip)
        if ($downloadPath -and (Test-Path -Path $downloadPath)) {
            Remove-Item -Path $downloadPath -Force
        }
    }
}

Export-ModuleMember -Function *-TargetResource
