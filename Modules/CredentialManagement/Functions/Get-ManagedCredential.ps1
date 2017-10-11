<#
.SYNOPSIS
Retrieves the managed credentials for the current user.
.DESCRIPTION
Retrieves the managed credentials for the current user.
.OUTPUTS
[CredentialManagement.CredentialManager+Credential[]]

.PARAMETER TargetName
Specifies the filter for the target-name of the managed credentials to retrieve.
The filter specifies a name prefix followed by an asterisk. For instance, the filter 'FRED*' will return all managed credentials with a TargetName beginning with the string 'FRED'. 
If no TargetName is specified, no filter will be applied for the target-name.
.PARAMETER CredentialType
Specifies the credential-type of the managed credentials to retrieve.
If no CredentialType is specified, no filter will be applied for the credential-type.
#>
function Get-ManagedCredential {
	param (
        [Parameter(Mandatory = $false)]
        [string]$TargetName,
		[Parameter(Mandatory = $false)]
        [ValidateSet('Generic', 'DomainPassword', 'DomainCertificate', 'DomainVisiblePassword', 'GenericCertificate', 'DomainExtended', 'Maximum', 'MaximumEx')]
        [string]$CredentialType
	)
	
    $result = 0
	$credentials = [CredentialManagement.CredentialManager]::GetCredentials($TargetName, [ref]$result)

	switch ($result) {
        0 { }
        0x80070490 { } #ERROR_NOT_FOUND
        default {
    		[string]$message = "Failed to enumerate managed credentials for user '$Env:USERNAME'."
    		[Management.ManagementException]$exception = New-Object -TypeName Management.ManagementException -ArgumentList $message
    		[Management.Automation.ErrorRecord]$errorRecord = New-Object -TypeName Management.Automation.ErrorRecord -ArgumentList $exception, $result.ToString("X"), $ErrorCategory[$result], $null
            throw $errorRecord
        }
	}

    if ($CredentialType) {
        $filterCredentialType = Convert-CredentialType $CredentialType
        $credentials = $credentials |? { $_.Type -eq $filterCredentialType }
    }

	return $credentials
}
