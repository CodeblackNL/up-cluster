<#
.SYNOPSIS
Deletes the specified managed credential for the current user.
.DESCRIPTION
Deletes the specified managed credential for the current user.

.PARAMETER TargetName
Specifies the URI of the managed credential to delete.
.PARAMETER CredentialType
Specifies the credential-type of the managed credentials to delete. Default is 'Generic'.
#>
function Remove-ManagedCredential {

	Param
	(
		[Parameter(Mandatory = $true, ParameterSetName = 'TargetName')]
        [ValidateLength(1,32767)]
        [string]$TargetName,
		[Parameter(Mandatory = $false, ParameterSetName = 'TargetName')]
        [ValidateSet('Generic', 'DomainPassword', 'DomainCertificate', 'DomainVisiblePassword', 'GenericCertificate', 'DomainExtended', 'Maximum', 'MaximumEx')]
        [string]$CredentialType = 'Generic',
		[Parameter(Mandatory = $true, ValueFromPipeline = $true, ParameterSetName = 'Pipeline')]
        $Credential
	)

    if ($Credential) {
        $TargetName = $Credential.TargetName
        $nativeType = $Credential.Type
    }
    else {
        $nativeType = Convert-CredentialType $CredentialType
    }

    $result = 0
	$credentials = [CredentialManagement.CredentialManager]::DeleteCredential($TargetName, $nativeType, [ref]$result)
	
	if ($result) {
		[string]$message = "Failed to delete credential for target '$TargetName'."
		[Management.ManagementException]$exception = New-Object Management.ManagementException($message)
    	[Management.Automation.ErrorRecord]$errorRecord = New-Object -TypeName Management.Automation.ErrorRecord -ArgumentList $exception, $result.ToString("X"), $ErrorCategory[$result], $null
        throw $errorRecord
	}
}
