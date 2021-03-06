Import-Module $PSScriptRoot\..\Helper.psm1 -Verbose:$false

function Get-TargetResource {
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Present', 'Absent')]
        [System.String]
        $Ensure = 'Present'
	)

    Assert-Module -moduleName DHCPServer

    $status = @{
        Ensure = 'Absent'
		ConfigurationState = 'Absent'
		DHCPUsersGroup = 'Absent'
		DHCPAdministratorsGroup = 'Absent'
	}
    
    $ensure = 'Absent'
    try {
		if ((Get-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\ServerManager\Roles\12 -Name ConfigurationState).ConfigurationState -eq 2) {
			$status.ConfigurationState = 'Present'
		}
    }
    catch { }

	$rootOU = [ADSI]"WinNT://$($env:COMPUTERNAME)"

    try {
        $groupUsers = [ADSI]"WinNT://$($env:COMPUTERNAME)/DHCP Users"
        if (!!$groupUsers.Name) {
			$status.DHCPUsersGroup = 'Present'
        }
    }
    catch { }

    try {
        $groupAdministrators = [ADSI]"WinNT://$($env:COMPUTERNAME)/DHCP Administrators"
        if (!!$groupAdministrators.Name) {
			$status.DHCPAdministratorsGroup = 'Present'
        }
    }
    catch { }
    
    if ($status.ConfigurationState -eq 'Present' -and `
        $status.DHCPUsersGroup -eq 'Present' -and `
        $status.DHCPAdministratorsGroup -eq 'Present') {
        $status.Ensure = 'Present'
    }

    return $status
}

function Test-TargetResource {
	[CmdletBinding()]
	[OutputType([System.Boolean])]
	param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Present', 'Absent')]
        [System.String]
        $Ensure = 'Present'
	)

    Assert-Module -moduleName DHCPServer

    $status = Get-TargetResource -Ensure $Ensure

    $result = $status.ConfigurationState -eq $Ensure -and `
              $status.DHCPUsersGroup -eq $Ensure -and `
              $status.DHCPAdministratorsGroup -eq $Ensure

    return $result
}

function Set-TargetResource {
	[CmdletBinding()]
	param (
        [Parameter(Mandatory = $true)]
        [ValidateSet('Present', 'Absent')]
        [System.String]
        $Ensure = 'Present'
	)

    Assert-Module -moduleName DHCPServer

    Write-Verbose -Message 'Checking DHCP configuration completion...'
    
	try {
		$rootOU = [ADSI]"WinNT://$($env:COMPUTERNAME)"
        $groupUsers = [ADSI]"WinNT://$($env:COMPUTERNAME)/DHCP Users"
        $groupAdministrators = [ADSI]"WinNT://$($env:COMPUTERNAME)/DHCP Administrators"

		$configurationState = (Get-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\ServerManager\Roles\12 -Name ConfigurationState).ConfigurationState
        if($Ensure -eq "Present" -and $configurationState -ne 2) {
            Write-Verbose -Message 'Completing DHCP configuration...'

            if (!$groupUsers.Name) {
		        $groupUsers = $rootOU.Create('Group','DHCP Users')
		        $groupUsers.CommitChanges()
            }
            if (!$groupAdministrators.Name) {
		        $groupAdministrators = $rootOU.Create('Group','DHCP Administrators')
		        $groupAdministrators.CommitChanges()
            }

			Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\ServerManager\Roles\12 -Name ConfigurationState -Value 2

            Write-Verbose -Message 'DHCP configuration is now completed'
        }
        elseif($Ensure -eq "Absent" -and $configurationState -ne 1) {
            Write-Verbose -Message 'Reversing completion if DHCP configuration...'

            if (!!$groupUsers.Name) {
                $rootOU.Children.Remove($groupUsers)
            }
            if (!!$groupAdministrators.Name) {
                $rootOU.Children.Remove($groupAdministrators)
            }

			Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\ServerManager\Roles\12 -Name ConfigurationState -Value 1

            Write-Verbose -Message 'DHCP configuration is not completed'
        }
	}
	catch { }
}

Export-ModuleMember -Function *-TargetResource