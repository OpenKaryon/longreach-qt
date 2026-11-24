# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
# Freeze the local loopback endpoint understood by both legacy frontends and ADB.

function Assert-AndroidAdbEndpoint($Endpoint) {
    $keys=if ($Endpoint -is [Collections.IDictionary]) { @($Endpoint.Keys) } else { @($Endpoint.PSObject.Properties.Name) }
    if (!$Endpoint -or $keys.Count -ne 4 -or @(Compare-Object @('host','port','schema_version','socket') @($keys | Sort-Object) -CaseSensitive).Count -or
            ($Endpoint.schema_version -isnot [int] -and $Endpoint.schema_version -isnot [long]) -or $Endpoint.schema_version -ne 1 -or
            $Endpoint.host -isnot [string] -or $Endpoint.host -cne 'localhost' -or
            ($Endpoint.port -isnot [int] -and $Endpoint.port -isnot [long]) -or $Endpoint.port -lt 1 -or $Endpoint.port -gt 65535 -or
            $Endpoint.socket -isnot [string] -or $Endpoint.socket -cne "tcp:localhost:$($Endpoint.port)") { throw 'Invalid frozen Android ADB endpoint' }
}

function Read-AndroidAdbEndpointRequest([string]$Path) {
    $bytes=[IO.File]::ReadAllBytes($Path)
    $algorithm=[Security.Cryptography.SHA256]::Create()
    try { $sha=[BitConverter]::ToString($algorithm.ComputeHash($bytes)).Replace('-','').ToLowerInvariant() }
    finally { $algorithm.Dispose() }
    return @{Sha=$sha;Record=([Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xfeff) | ConvertFrom-Json)}
}

function Get-AndroidAdbEndpoint {
    param([Collections.IDictionary]$Environment)
    if ($null -eq $Environment) {
        $Environment=@{}
        foreach ($name in @('ADB_SERVER_SOCKET','ANDROID_ADB_SERVER_ADDRESS','ANDROID_ADB_SERVER_PORT')) {
            $Environment[$name]=[Environment]::GetEnvironmentVariable($name)
        }
    }
    $socket=[string]$Environment['ADB_SERVER_SOCKET']
    $address=[string]$Environment['ANDROID_ADB_SERVER_ADDRESS']
    $portText=[string]$Environment['ANDROID_ADB_SERVER_PORT']
    if ($address -and $address -cnotin @('localhost','127.0.0.1')) { throw 'Local emulator qualification requires a local IPv4 ADB server' }
    $socketPort=$null
    if ($socket) {
        if ($socket -cmatch '^tcp:(?:(?:localhost|127\.0\.0\.1):)?([0-9]+)$') { $socketPort=$Matches[1] }
        else { throw 'Local emulator qualification requires a local IPv4 TCP ADB socket' }
    }
    $port=5037
    foreach ($value in @($socketPort,$portText)) {
        if (!$value) { continue }
        $number=0
        if ($value -cnotmatch '^[0-9]+$' -or ![int]::TryParse($value,[ref]$number) -or $number -lt 1 -or $number -gt 65535) { throw 'Invalid Android ADB server port' }
        if ($value -ceq $portText -and $socketPort -and $number -ne [int]$socketPort) { throw 'ADB socket and legacy frontend server port disagree' }
        $port=$number
    }
    $endpoint=@{schema_version=1;host='localhost';port=[int]$port;socket="tcp:localhost:$port"}
    Assert-AndroidAdbEndpoint $endpoint
    return $endpoint
}

function Set-AndroidAdbEndpointContext {
    param([Parameter(Mandatory)][string]$Directory,[Parameter(Mandatory)]$Endpoint,[string]$RequestSha)
    Assert-AndroidAdbEndpoint $Endpoint
    $endpointCopy=@{schema_version=1;host='localhost';port=[int]$Endpoint.port;socket=[string]$Endpoint.socket}
    $global:LongreachAndroidAdbContext=@{Directory=[IO.Path]::GetFullPath($Directory);Endpoint=$endpointCopy;RequestSha=$RequestSha}
}

function Clear-AndroidAdbEndpointContext([string]$Directory,[string]$RequestSha) {
    if ($global:LongreachAndroidAdbContext -and $global:LongreachAndroidAdbContext.Directory -eq [IO.Path]::GetFullPath($Directory) -and
            (!$RequestSha -or $global:LongreachAndroidAdbContext.RequestSha -ceq $RequestSha)) {
        Remove-Variable LongreachAndroidAdbContext -Scope Global -ErrorAction SilentlyContinue
    }
}

function Get-AndroidAdbArguments {
    param([AllowEmptyCollection()][string[]]$Arguments=@(),[string]$Directory,$Endpoint)
    $context=$global:LongreachAndroidAdbContext
    if ($Directory) {
        $directoryKey=[IO.Path]::GetFullPath($Directory)
        $inside=$false
        if ($context) {
            $relative=[IO.Path]::GetRelativePath($context.Directory,$directoryKey)
            $inside=![IO.Path]::IsPathRooted($relative) -and $relative -ne '..' -and !$relative.StartsWith('..'+[IO.Path]::DirectorySeparatorChar,[StringComparison]::Ordinal)
        }
        if (!$inside) {
            $context=$null
            $probe=$directoryKey
            while ($probe) {
                $path=Join-Path $probe 'host-process-request.json'
                if (Test-Path -LiteralPath $path) {
                    $snapshot=Read-AndroidAdbEndpointRequest $path
                    $sha=$snapshot.Sha;$request=$snapshot.Record
                    $owner=Get-Content -LiteralPath (Join-Path $probe 'host-process-owner.json') -Raw | ConvertFrom-Json
                    if ($owner.request_sha256 -cne $sha -or $owner.run_id -cne $request.run_id) { throw 'ADB endpoint request differs from its owned launch' }
                    if ($owner.adb_endpoint_applied_before_start -isnot [bool] -or !$owner.adb_endpoint_applied_before_start) { throw 'Frozen ADB endpoint was not applied before frontend startup' }
                    Set-AndroidAdbEndpointContext -Directory $probe -Endpoint $request.adb_endpoint -RequestSha $sha
                    $context=$global:LongreachAndroidAdbContext
                    break
                }
                $parent=[IO.Directory]::GetParent($probe)
                $probe=if ($parent) { $parent.FullName } else { $null }
            }
        }
    }
    if ($Endpoint) {
        Assert-AndroidAdbEndpoint $Endpoint
        if ($context -and ($context.Endpoint.port -ne $Endpoint.port -or $context.Endpoint.socket -cne $Endpoint.socket)) {
            throw 'An active frozen ADB endpoint cannot be overridden'
        }
        if (!$context) { $context=@{Endpoint=$Endpoint;RequestSha=$null} }
    }
    if (!$context -and $Directory) {
        throw 'No frozen ADB endpoint found for the specified owned run directory'
    }
    if (!$context) { return $Arguments } # Calls without a run directory remain diagnostics.
    Assert-AndroidAdbEndpoint $context.Endpoint
    if ($context.RequestSha) {
        $snapshot=Read-AndroidAdbEndpointRequest (Join-Path $context.Directory 'host-process-request.json')
        if ($snapshot.Sha -cne $context.RequestSha) { throw 'ADB endpoint request changed after owned launch' }
        Assert-AndroidAdbEndpoint $snapshot.Record.adb_endpoint
        if ($context.Endpoint.port -ne $snapshot.Record.adb_endpoint.port -or $context.Endpoint.socket -cne $snapshot.Record.adb_endpoint.socket) {
            throw 'Current ADB endpoint differs from its frozen request'
        }
    }
    # Reject endpoint overrides only in the global option prefix, not shell argv.
    $index=0
    while ($index -lt $Arguments.Count -and $Arguments[$index].StartsWith('-',[StringComparison]::Ordinal)) {
        $option=$Arguments[$index]
        if ($option -cmatch '^-(?:H|P|L)') { throw 'A frozen ADB endpoint cannot be overridden by client options' }
        if ($option -in @('-s','-t')) { $index+=2 } elseif ($option -in @('-a','-d','-e')) { $index++ } else { break }
    }
    return @('-H','localhost','-P',[string]$context.Endpoint.port)+$Arguments
}
