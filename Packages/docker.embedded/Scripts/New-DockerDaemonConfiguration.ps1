
function New-DockerDaemonConfiguration {
    param (
        [string]
        $FilePath = 'C:\ProgramData\docker\config\daemon.json',

        [Hashtable]
        $ConfigurationParameters
    )

    $daemonConfiguration = @{}

    foreach ($key in $ConfigurationParameters.Keys) {
        if ($key -in 'experimental','debug','tlsverify','raw-logs','disable-legacy-registry') {
            # [bool]
            $daemonConfiguration.$key = ($ConfigurationParameters.$key -eq 'true')
        }
        elseif ($key -in 'mtu','max-concurrent-downloads','max-concurrent-uploads','shutdown-timeout') {
            # [int]
            $value = 0
            if ([int]::TryParse($ConfigurationParameters.$key, [ref]$value)) {
                $daemonConfiguration.$key = $value
            }
        }
        elseif ($key -in 'authorization-plugins','dns','dns-opts','dns-search','exec-opts','storage-opts','labels','hosts','default-ulimits','allow-nondistributable-artifacts','registry-mirrors','insecure-registries') {
            # [array]
            $daemonConfiguration.$key = @($ConfigurationParameters.$key.Split(@(';',',')))
        }
        else {
            # [string]
            $daemonConfiguration.$key = $ConfigurationParameters.$key
        }
    }

    New-Item -Path (Split-Path -Path $FilePath -Parent) -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    $daemonConfiguration | ConvertTo-Json -Depth 9 | Out-File -FilePath $FilePath -Force -Encoding ascii
}
