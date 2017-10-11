function Convert-CredentialType {
    param (
		[Parameter(Mandatory=$true)]
        [ValidateSet('Generic', 'DomainPassword', 'DomainCertificate', 'DomainVisiblePassword', 'GenericCertificate', 'DomainExtended', 'Maximum', 'MaximumEx')]
        [string]$CredentialType
    )

	switch ($CredentialType) {
		'Generic'               { return [CredentialManagement.CredentialManager+CRED_TYPE]::GENERIC }
		'DomainPassword'        { return [CredentialManagement.CredentialManager+CRED_TYPE]::DOMAIN_PASSWORD }
		'DomainCertificate'     { return [CredentialManagement.CredentialManager+CRED_TYPE]::DOMAIN_CERTIFICATE }
		'DomainVisiblePassword' { return [CredentialManagement.CredentialManager+CRED_TYPE]::DOMAIN_VISIBLE_PASSWORD }
		'GenericCertificate'    { return [CredentialManagement.CredentialManager+CRED_TYPE]::GENERIC_CERTIFICATE }
		'DomainExtended'        { return [CredentialManagement.CredentialManager+CRED_TYPE]::DOMAIN_EXTENDED }
		'Maximum'               { return [CredentialManagement.CredentialManager+CRED_TYPE]::MAXIMUM }
		'MaximumEx'             { return [CredentialManagement.CredentialManager+CRED_TYPE]::MAXIMUM_EX }
	}
}
