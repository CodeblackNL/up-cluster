<#
.SYNOPSIS
Creates a new managed credential for the current user.
.DESCRIPTION
Creates a new managed credential for the current user.
.OUTPUTS
[CredentialManagement.CredentialManager+Credential]

.PARAMETER TargetName
Specifies the URI for which the managed credential is created. If not provided, the user-name is used as the target.
.PARAMETER UserName
Specifies the user-name of the new managed credential.
.PARAMETER Password
Specifies the password of the new managed credential.
.PARAMETER Comment
Specifies the comment of the new managed credential. If not provided, a comment is created based on the current user and the current machine.
.PARAMETER CredentialType
Specifies the desired credential-type of the new managed credential. Default is 'Generic'.
.PARAMETER Persist
Specifies whether the new managed credential should be persisted.
If false, or not provided, the new managed credential is only persisted for the life of the logon session.
If true, or present, the new managed credential is persisted based on the value of the PersistanceScope parameter.
See 'https://msdn.microsoft.com/en-us/library/windows/desktop/aa374788(v=vs.85).aspx' for more details.
.PARAMETER PersistanceScope
Specifies how the new managed credential should be persisted. Only valid if the Persist parameter is present, or true. Default value is 'Enterprise'.
See 'https://msdn.microsoft.com/en-us/library/windows/desktop/aa374788(v=vs.85).aspx' for more details.
#>
function New-ManagedCredential {
	param (
		[Parameter(Mandatory = $false)][ValidateLength(0,32676)]
        [string]$TargetName,
		[Parameter(Mandatory = $true)][ValidateLength(1,512)]
        [string]$UserName,
		[Parameter(Mandatory = $true)][ValidateLength(1,512)]
        [string]$Password,
		[Parameter(Mandatory=$false)][ValidateLength(0,256)]
        [string]$Comment,
		[Parameter(Mandatory = $false)]
        [ValidateSet('Generic', 'DomainPassword', 'DomainCertificate', 'DomainVisiblePassword', 'GenericCertificate', 'DomainExtended', 'Maximum', 'MaximumEx')]
        [string]$CredentialType = 'Generic',
		[Parameter(Mandatory = $true, ParameterSetName = 'Persist')]
        [switch]$Persist,
		[Parameter(Mandatory = $false, ParameterSetName = 'Persist')]
        [ValidateSet('LocalMachine', 'Enterprise')]
        [string]$PersistanceScope = 'LocalMachine'
	)

	if (-not $TargetName) {
		$TargetName = $UserName
	}
	if ($CredentialType -ne 'Generic' -and $TargetName.Length -ge 337) { # CRED_MAX_DOMAIN_TARGET_NAME_LENGTH
		[string]$message = "Target field is longer ($($TargetName.Length)) than allowed (max 337 characters)."
		[Management.ManagementException]$exception = New-Object Management.ManagementException($message)
    	[Management.Automation.ErrorRecord]$errorRecord = New-Object -TypeName Management.Automation.ErrorRecord -ArgumentList $exception, $result.ToString("X"), $ErrorCategory[$result], $null
        throw $errorRecord
	}
    if (-not $Comment) {
        $Comment = 'Last edited by {0}\{1} on {2}' -f $Env:UserDomain,$Env:UserName,$Env:ComputerName
    }

	[CredentialManagement.CredentialManager+Credential]$credential = New-Object -TypeName CredentialManagement.CredentialManager+Credential
    $credential.Type = Convert-CredentialType $CredentialType
	$credential.TargetName = $TargetName
	$credential.UserName = $UserName
	$credential.AttributeCount = 0
	$credential.Flags = [CredentialManagement.CredentialManager+CRED_FLAGS]::NONE
    if (-not $Persist.IsPresent) {
	    $credential.Persist = [CredentialManagement.CredentialManager+CRED_PERSIST]::SESSION
    }
    elseif ($PersistanceScope -eq 'Enterprise') {
	    $credential.Persist = [CredentialManagement.CredentialManager+CRED_PERSIST]::ENTERPRISE
    }
    else {
	    $credential.Persist = [CredentialManagement.CredentialManager+CRED_PERSIST]::LOCAL_MACHINE
    }
	$credential.CredentialBlobSize = [Text.Encoding]::Unicode.GetBytes($Password).Length
	$credential.CredentialBlob = $Password
	$credential.Comment = $Comment

    $result = 0
	[CredentialManagement.CredentialManager]::WriteCredential($credential, [ref]$result)

	if ($result) {
		[string]$message = "Failed to create credential for target '$TargetName' using '$UserName', '$($credential.Type)', '$($credential.Persist)', '$Comment'"
		[Management.ManagementException]$exception = New-Object Management.ManagementException($message)
    	[Management.Automation.ErrorRecord]$errorRecord = New-Object -TypeName Management.Automation.ErrorRecord -ArgumentList $exception, $result.ToString("X"), $ErrorCategory[$result], $null
        throw $errorRecord
	}

    return $credential
}
