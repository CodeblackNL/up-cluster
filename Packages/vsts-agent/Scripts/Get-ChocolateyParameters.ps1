
function Get-ChocolateyParameters {
    param (
        [string]$PackageParameters = $env:chocolateyPackageParameters
    )

    Write-Host "Parameters: '$PackageParameters'"
    $parameters = @{}

    if ($PackageParameters) {
        $matchPattern = "(--|-|\/)(?<option>([a-zA-Z-]+))(=)(?<value>([`"'])?([a-zA-Z0-9- _\\/:;,\.]+)([`"'])?)|(--|-|\/)(?<option>([a-zA-Z]+))"
        $optionName = 'option'
        $valueName = 'value'

        if ($PackageParameters -match $matchPattern ) {
            $results = $PackageParameters | Select-String $matchPattern -AllMatches
            $results.Matches | ForEach-Object {
                $option = $_.Groups[$optionName].Value.Trim()
                $value = $_.Groups[$valueName].Value.Trim()

                if ($value -eq 'false') {
                    $value = $false
                }
                elseif ($value -eq 'true') {
                    $value = $true
                }
                elseif ($value -and (($value.StartsWith("'") -and $value.EndsWith("'")) -or
                                     ($value.StartsWith('"') -and $value.EndsWith('"')))) {
                    $value = $value.Trim('''"')
                }

                if ($parameters.ContainsKey($option)) {
                    $existingValue = $parameters[$option]
                    if ($existingValue -isnot [Array]) {
                        $existingValue = @($existingValue)
                    }
                    $existingValue += $value
                    $parameters.$option = $existingValue
                }
                else {
                    $parameters.$option = $value
                }
            }
        }
        else {
            throw "Package-parameters were found but were invalid (REGEX Failure)."
        }

        foreach ($key in $parameters.Keys) {
            Write-Host "Parameter: $key = '$($parameters.$key)' [$($parameters.$key.GetType().Name)]"
        }
    }
    else {
        Write-Verbose "No package-parameters provided."
    }

    return $parameters
}