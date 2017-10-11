param (
	[switch]$Force
)

$modulesPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Files.Disk\Provisioning\Modules'
$modulesSourcePath = Join-Path -Path $PSScriptRoot -ChildPath '..\Files.Disk\InstallationShare\Modules'

$modules = @(
    @{ Name = 'Docker';                       Version = '0.1.0.111'; Source = 'https://ci.appveyor.com/nuget/docker-powershell-dev' }
    @{ Name = 'PackageManagement';            Version = '1.1.4.0' }
    @{ Name = 'xActiveDirectory';             Version = '2.16.0.0' }
    @{ Name = 'xComputerManagement';          Version = '2.0.0.0' }
    @{ Name = 'xCredSSP';                     Version = '1.3.0.0' }
    @{ Name = 'xDhcpServer';                  Version = '1.5.0.0' }
    @{ Name = 'xDnsServer';                   Version = '1.7.0.0' }
    @{ Name = 'xNetworking';                  Version = '5.0.0.0' }
    @{ Name = 'xPSDesiredStateConfiguration'; Version = '6.4.0.0' }
    @{ Name = 'xRemoteDesktopAdmin';          Version = '1.1.0.0' }
    @{ Name = 'xSmbShare';                    Version = '2.0.0.0' }
    @{ Name = 'xSQLServer';                   Version = '8.0.0.0' }
    @{ Name = 'xWebAdministration';           Version = '1.18.0.0' }
)

foreach ($module in $modules) {
    Write-Host "Retrieving module '$($module.Name)' ($($module.Version))..."

	$filePath = Join-Path -Path $modulesPath -ChildPath "$($module.Name).$($module.Version).nupkg"
	if ($Force.IsPresent -or -not (Test-Path -Path $filePath -PathType Leaf)) {
		$foundModules = Find-Module -Name $module.Name
		if (-not $foundModules) {
			Write-Warning "Module '$($module.Name)' not found."
			continue
		}

		$foundModule = $foundModules | Where-Object { $_.Version -eq [Version]$module.Version } | Select-Object -First 1
		Write-Host "Found module '$($foundModule.Name)' ($($foundModule.Version))..." -ForegroundColor Green

		$latestModule = $foundModules | Sort-Object Version | Select-Object -Last 1
		if ($latestModule.Version -gt [Version]$module.Version) {
			Write-Warning "Module '$($module.Name)' found, but a more recent version ($($latestModule.Version)) exists then requested ($($module.Version))."
		}

		if ($module.Source) {
			$packageSource = $module.Source
		}
		else {
			$packageSource = 'http://www.powershellgallery.com/api/v2'
		}
		
		#$packageUrl = "http://www.powershellgallery.com/api/v2/Packages(Id='$($foundModule.Name)',Version='$($module.Version)')"
		$packageUrl = "$($packageSource.TrimEnd('/'))/Packages(Id='$($foundModule.Name)',Version='$($module.Version)')"
		$packageResponse = Invoke-RestMethod -Uri $packageUrl
		$downloadUrl = $packageResponse.entry.content.src
		Write-Host "Downloading module '$($foundModule.Name)' ($($module.Version)) from '$downloadUrl'..."
		Invoke-WebRequest -Uri $downloadUrl -OutFile $filePath
		Copy-Item -Path $filePath -Destination (Join-Path -Path $modulesSourcePath -ChildPath (Split-Path -Path $filePath -Leaf))
	}
	else {
		Write-Host "Module '$($foundModule.Name)' ($($module.Version)) already downloaded."
	}
}