enum Ensure {
    Absent
    Present
}

enum CredentialType {
    Generic
    DomainPassword
    DomainCertificate
    DomainVisiblePassword
    GenericCertificate
    DomainExtended
    Maximum
    MaximumEx
}

enum PersistanceScope {
    LocalMachine
    Enterprise
}

function Get-TargetResource {
    [OutputType([System.Collections.Hashtable])]
    param (        
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetName
    )

    $returnValue = @{
        TargetName = $TargetName
        Ensure = 'Absent'
    }

    $managedCredential = Get-ManagedCredential -TargetName $TargetName
    if ($managedCredential) {
        $returnValue.Ensure = 'Present'
        $returnValue.UserName = $managedCredential.UserName
        $returnValue.CredentialType = $managedCredential.Type
        $returnValue.Persist = $false
        switch ($managedCredential.Persist) {
            'LOCAL_MACHINE' {
                $returnValue.PersistanceScope = 'LocalMachine'
                $returnValue.Persist = $true
            }
            'ENTERPRISE' {
                $returnValue.PersistanceScope = 'Enterprise'
                $returnValue.Persist = $true
            }
        }

    }

    $returnValue
}

function Test-TargetResource {
    param (        
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetName,
        [Ensure]$Ensure = 'Present',
        [Parameter(Mandatory)]
        [PSCredential]$Credential,
        [CredentialType]$CredentialType,
        [bool]$Persist,
        [PersistanceScope]$PersistanceScope
    )

    if ($PersistanceScope -in [PersistanceScope]::LocalMachine,[PersistanceScope]::Enterprise) {
        $Persist = $true
    }

    $managedCredential = Get-ManagedCredential -TargetName $TargetName

    if ($Ensure -eq 'Absent') {
        if ($managedCredential) {
            Write-Verbose "Managed-credential found for '$TargetName', while it should be $Ensure"
            return $false
        }
    }
    else {
        if (-not $managedCredential) {
            Write-Verbose "Managed-credential for '$TargetName' not found, while it should be $Ensure"
            return $false
        }
        if ($managedCredential.UserName -ne $Credential.UserName) {
            Write-Verbose "Managed-credential found for '$TargetName', but user-name is different"
            return $false
        }
        if ((Convert-CredentialType -CredentialType $managedCredential.Type) -ne $CredentialType) {
            Write-Verbose "Managed-credential found for '$TargetName', but credential-type is different"
            return $false
        }
        if ((Convert-PersistanceScope -PersistanceScope $managedCredential.Persist) -ne $PersistanceScope) {
            Write-Verbose "Managed-credential found for '$TargetName', but persistance-scope is different"
            return $false
        }
    }

    return $true
}

function Set-TargetResource {
    param (        
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TargetName,
        [Ensure]$Ensure = 'Present',
        [Parameter(Mandatory)]
        [PSCredential]$Credential,
        [CredentialType]$CredentialType,
        [bool]$Persist,
        [PersistanceScope]$PersistanceScope
    )

    if ($PersistanceScope -eq [PersistanceScope]::LocalMachine -or $PersistanceScope -eq [PersistanceScope]::Enterprise) {
        $Persist = $true
    }

    $managedCredential = Get-ManagedCredential -TargetName $TargetName
    if ($managedCredential) {
        Write-Verbose "Removing managed-credential for '$TargetName'"
        $managedCredential | Remove-ManagedCredential
    }

    if ($Ensure -eq 'Present') {
        Write-Verbose "Creating managed-credential for '$TargetName'"
        if ($Persist) {
            New-ManagedCredential `
                -TargetName $TargetName `
                -UserName $Credential.UserName `
                -Password $Credential.GetNetworkCredential().Password `
                -CredentialType $CredentialType `
                -Persist -PersistanceScope $PersistanceScope
        }
        else {
            New-ManagedCredential `
                -TargetName $TargetName `
                -UserName $Credential.UserName `
                -Password $Credential.GetNetworkCredential().Password `
                -CredentialType $CredentialType
        }

        $managedCredential = Get-ManagedCredential -TargetName $TargetName
    }
}

function Convert-CredentialType {
    param (
        [string]$CredentialType
    )

	switch ($CredentialType) {
		'GENERIC'                 { return 'Generic' }
		'DOMAIN_PASSWORD'         { return 'DomainPassword' }
		'DOMAIN_CERTIFICATE'      { return 'DomainCertificate' }
		'DOMAIN_VISIBLE_PASSWORD' { return 'DomainVisiblePassword' }
		'GENERIC_CERTIFICATE'     { return 'GenericCertificate' }
		'DOMAIN_EXTENDED'         { return 'DomainExtended' }
		'MAXIMUM'                 { return 'Maximum' }
		'MAXIMUM_EX'              { return 'MaximumEx' }
        default                   { return $CredentialType }
	}
}

function Convert-PersistanceScope {
    param (
        [string]$PersistanceScope
    )

	switch ($PersistanceScope) {
		'LOCAL_MACHINE' { return 'LocalMachine' }
		'ENTERPRISE'    { return 'Enterprise' }
        default         { return 'Session' }
	}
}
