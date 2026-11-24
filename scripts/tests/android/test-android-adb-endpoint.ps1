# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
# Ordinary endpoint/argv metadata and hidden Python environment fixtures only.
param([string]$RepoRoot=(Resolve-Path "$PSScriptRoot/../../..").Path)
$ErrorActionPreference='Stop'
. "$RepoRoot/scripts/run/android/android-adb.ps1"
. "$RepoRoot/scripts/run/android/android-process-exit.ps1"
. "$RepoRoot/scripts/run/android/android-wait-boot.ps1"
. "$RepoRoot/scripts/run/android/android-owned-process.ps1"
$parent=[IO.Path]::GetTempPath().TrimEnd('\','/')
$fixture=Join-Path $parent ('longreach-adb-endpoint-'+[guid]::NewGuid())
$control=$null
$previousContext=$global:LongreachAndroidAdbContext
$previousEnvironment=@{}
foreach ($name in @('ADB_SERVER_SOCKET','ANDROID_ADB_SERVER_ADDRESS','ANDROID_ADB_SERVER_PORT','LONGREACH_ENDPOINT_FIXTURE')) {
    $previousEnvironment[$name]=[Environment]::GetEnvironmentVariable($name)
}
$script:EndpointQueries=[Collections.Generic.List[object]]::new()
function Assert-Endpoint([bool]$Condition,[string]$Message) { if (!$Condition) { throw $Message } }
function Refuse-Endpoint([scriptblock]$Action,[string]$Pattern) {
    try { & $Action | Out-Null } catch { Assert-Endpoint ($_.Exception.Message -match $Pattern) "Unexpected endpoint error: $_";return }
    throw 'Expected endpoint refusal'
}
function Start-Process {
    param($FilePath,[string[]]$ArgumentList,$WindowStyle,[switch]$PassThru,$RedirectStandardOutput,$RedirectStandardError)
    $script:EndpointQueries.Add(@($ArgumentList))
    Assert-Endpoint ($WindowStyle -eq 'Hidden') 'Query requested a visible window'
    [IO.File]::WriteAllText($RedirectStandardOutput,"1`n")
    [IO.File]::WriteAllText($RedirectStandardError,'')
    $process=[pscustomobject]@{HasExited=$true;ExitCode=0}
    $process | Add-Member ScriptMethod WaitForExit { param($Milliseconds);return $true }
    $process | Add-Member ScriptMethod Dispose { }
    return $process
}
function Stop-Process { throw 'Inert endpoint query requested a process stop' }
try {
    New-Item -ItemType Directory -Path $fixture | Out-Null
    foreach ($case in @(
        @{env=@{};port=5037},
        @{env=@{ANDROID_ADB_SERVER_PORT='5048'};port=5048},
        @{env=@{ANDROID_ADB_SERVER_PORT='05048'};port=5048},
        @{env=@{ADB_SERVER_SOCKET='tcp:localhost:5048'};port=5048},
        @{env=@{ADB_SERVER_SOCKET='tcp:127.0.0.1:5048';ANDROID_ADB_SERVER_PORT='5048'};port=5048},
        @{env=@{ADB_SERVER_SOCKET='tcp:5048';ANDROID_ADB_SERVER_ADDRESS='localhost'};port=5048},
        @{env=@{ANDROID_ADB_SERVER_PORT='65535'};port=65535})) {
        $value=Get-AndroidAdbEndpoint -Environment $case.env
        Assert-Endpoint ($value.port -eq $case.port -and $value.socket -ceq "tcp:localhost:$($case.port)") 'Endpoint selection changed'
        Assert-AndroidAdbEndpoint ($value | ConvertTo-Json | ConvertFrom-Json)
    }
    foreach ($environment in @(
        @{ADB_SERVER_SOCKET='tcp:localhost:5048';ANDROID_ADB_SERVER_PORT='5037'},
        @{ADB_SERVER_SOCKET='tcp:192.0.2.1:5048'},@{ANDROID_ADB_SERVER_ADDRESS='192.0.2.1'},
        @{ADB_SERVER_SOCKET='tcp:[::1]:5048'},@{ADB_SERVER_SOCKET='localfilesystem:fixture'},
        @{ANDROID_ADB_SERVER_PORT='0'},@{ANDROID_ADB_SERVER_PORT='65536'},@{ANDROID_ADB_SERVER_PORT=' 5048'},
        @{ANDROID_ADB_SERVER_PORT='0x13b8'},@{ANDROID_ADB_SERVER_PORT='999999999999999999999'},
        @{ADB_SERVER_SOCKET='tcp:localhost:not-a-number'})) {
        Refuse-Endpoint { Get-AndroidAdbEndpoint -Environment $environment } 'requires|Invalid|disagree'
    }
    $endpoint=Get-AndroidAdbEndpoint -Environment @{ANDROID_ADB_SERVER_PORT='5048'}
    Set-AndroidAdbEndpointContext -Directory $fixture -Endpoint $endpoint
    $info=New-AndroidAdbClientStartInfo -Adb 'data-only-adb.exe' -Arguments @('-s','emulator-5582','shell','echo','two words','-P')
    Assert-Endpoint (($info.ArgumentList -join '|') -ceq '-H|localhost|-P|5048|-s|emulator-5582|shell|echo|two words|-P') 'Client argv did not preserve its frozen endpoint/operands'
    Assert-Endpoint (!$info.UseShellExecute -and $info.CreateNoWindow) 'Client start info became interactive'
    foreach ($arguments in @(@('-P','5037','devices'),@('-s','emulator-5582','-H','localhost','shell','id'),@('-Ltcp:5037','devices'))) {
        Refuse-Endpoint { New-AndroidAdbClientStartInfo -Adb data-only-adb.exe -Arguments $arguments } 'cannot be overridden'
    }
    Refuse-Endpoint { New-AndroidAdbClientStartInfo -Adb data-only-adb.exe -Arguments @('devices') -Endpoint (Get-AndroidAdbEndpoint -Environment @{}) } 'cannot be overridden'
    $lines=@(Invoke-AndroidExitQuery -Adb data-only-adb.exe -Serial emulator-5582 -Command @('shell','ps') -Directory $fixture -Name recorded-exit)
    Assert-Endpoint ($lines.Count -eq 1 -and $lines[0] -eq '1') 'Exit-query fixture changed'
    $caseDirectory=(New-Item -ItemType Directory -Path "$fixture/nested case").FullName
    Invoke-AndroidExitQuery -Adb data-only-adb.exe -Serial emulator-5582 -Command @('shell','ps') -Directory $caseDirectory -Name nested-exit | Out-Null
    $self=[Diagnostics.Process]::GetCurrentProcess()
    try { Wait-AndroidBoot -Adb data-only-adb.exe -Serial emulator-5582 -RunDirectory $fixture -EmulatorPid $PID -EmulatorProcess $self -TimeoutSeconds 1 }
    finally { $self.Dispose() }
    Assert-Endpoint ($script:EndpointQueries.Count -eq 3) 'Expected actual boot/exit helper launch boundaries'
    foreach ($arguments in $script:EndpointQueries) {
        Assert-Endpoint (($arguments[0..3] -join '|') -ceq '-H|localhost|-P|5048') 'Boot/exit query skipped endpoint binding'
    }
    Clear-AndroidAdbEndpointContext $fixture
    Assert-Endpoint ((Get-AndroidAdbArguments -Arguments @('version')) -ceq 'version') 'Unbound diagnostic argv was changed'
    Set-AndroidAdbEndpointContext -Directory $fixture -Endpoint $endpoint -RequestSha ('b'*64)
    Clear-AndroidAdbEndpointContext $fixture -RequestSha ('a'*64)
    Assert-Endpoint ($global:LongreachAndroidAdbContext.RequestSha -ceq ('b'*64)) 'Stale cleanup cleared a newer endpoint owner'
    Clear-AndroidAdbEndpointContext $fixture -RequestSha ('b'*64)
    if ($IsWindows) {
        $run=(New-Item -ItemType Directory -Path "$fixture/owned frontend").FullName
        # Deliberately different ambient values must not reach the declared child.
        $env:ADB_SERVER_SOCKET='tcp:localhost:5999';$env:ANDROID_ADB_SERVER_PORT='5999'
        $env:ANDROID_ADB_SERVER_ADDRESS='localhost';$env:LONGREACH_ENDPOINT_FIXTURE='кириллица'
        $python=(Get-Command python -CommandType Application | Select-Object -First 1).Source
        $code='import json,os; print(json.dumps({k:os.environ.get(k) for k in ("ADB_SERVER_SOCKET","ANDROID_ADB_SERVER_PORT","ANDROID_ADB_SERVER_ADDRESS","LONGREACH_ENDPOINT_FIXTURE")},ensure_ascii=True))'
        $control=Start-AndroidOwnedProcess -Program $python -Arguments @('-c',$code) -Directory $run -AdbEndpoint $endpoint
        $native=$control
        $applied=Get-Content "$run/host-process-request.json" -Raw | ConvertFrom-Json
        Assert-Endpoint ($applied.adb_endpoint.port -eq 5048 -and $native.Owner.adb_endpoint_applied_before_start) 'Owned launch did not bind endpoint'
        $env:ANDROID_ADB_SERVER_PORT='5998';$env:ADB_SERVER_SOCKET='tcp:localhost:5998'
        $info=New-AndroidAdbClientStartInfo -Adb data-only-adb.exe -Arguments @('-s','serial','shell','id')
        Assert-Endpoint ($info.ArgumentList[3] -eq '5048') 'Ambient drift changed bound client target'
        Remove-Variable LongreachAndroidAdbContext -Scope Global
        $ownerBytes=[IO.File]::ReadAllBytes("$run/host-process-owner.json")
        try {
            $ownerRecord=Get-Content "$run/host-process-owner.json" -Raw | ConvertFrom-Json
            $ownerRecord.adb_endpoint_applied_before_start=$false
            [IO.File]::WriteAllText("$run/host-process-owner.json",($ownerRecord | ConvertTo-Json -Depth 8))
            Refuse-Endpoint { Get-AndroidAdbArguments -Arguments @('shell','id') -Directory $run } 'not applied before'
        } finally { [IO.File]::WriteAllBytes("$run/host-process-owner.json",$ownerBytes) }
        $nestedRun=(New-Item -ItemType Directory -Path (Join-Path $run 'case')).FullName
        $reattached=@(Get-AndroidAdbArguments -Arguments @('shell','id') -Directory $nestedRun)
        Assert-Endpoint ($reattached[3] -eq '5048') 'Fresh context did not read the frozen request'
        $request=[IO.File]::ReadAllBytes("$run/host-process-request.json")
        try {
            [IO.File]::AppendAllText("$run/host-process-request.json","`n")
            Refuse-Endpoint { New-AndroidAdbClientStartInfo -Adb data-only-adb.exe -Arguments @('devices') } 'changed after owned launch'
        } finally { [IO.File]::WriteAllBytes("$run/host-process-request.json",$request) }
        Stop-AndroidOwnedProcess $control -GraceMilliseconds 0 | Out-Null
        $control=$null
        $observed=Get-Content "$run/emulator.stdout" -Raw | ConvertFrom-Json
        Assert-Endpoint ($observed.ADB_SERVER_SOCKET -ceq 'tcp:localhost:5048' -and $observed.ANDROID_ADB_SERVER_PORT -eq '5048' -and $observed.ANDROID_ADB_SERVER_ADDRESS -eq 'localhost') 'Frontend inherited the wrong endpoint'
        Assert-Endpoint ($observed.LONGREACH_ENDPOINT_FIXTURE -ceq 'кириллица') 'Unicode/inherited environment was lost'
        Assert-Endpoint (!$global:LongreachAndroidAdbContext) 'Completed owner retained an ambient endpoint context'
    }
    Write-Output 'PASS: endpoint parsing/consistency, exact client/boot/exit argv, owned frontend environment, reattachment and drift refusal'
} finally {
    if ($control) { Stop-AndroidOwnedProcess $control -GraceMilliseconds 0 | Out-Null }
    foreach ($name in $previousEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name,$previousEnvironment[$name]) }
    $global:LongreachAndroidAdbContext=$previousContext
    if (Test-Path -LiteralPath $fixture) {
        $resolved=(Resolve-Path -LiteralPath $fixture).Path
        if ([IO.Path]::GetDirectoryName($resolved) -ne $parent -or [IO.Path]::GetFileName($resolved) -notlike 'longreach-adb-endpoint-*') { throw 'Unexpected endpoint fixture cleanup path' }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
