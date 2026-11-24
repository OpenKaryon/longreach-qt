# SPDX-License-Identifier: GPL-3.0-or-later
<# Exercise real child timeouts and boot-log failures without an emulator. #>
param([string]$RepoRoot=(Resolve-Path "$PSScriptRoot/../../..").Path)
$ErrorActionPreference='Stop'
. "$RepoRoot/scripts/run/android/android-wait-boot.ps1"
$parent=(New-Item -ItemType Directory -Force "$RepoRoot/build/fixtures").FullName
$fixture=Join-Path $parent ('android-ready-'+[guid]::NewGuid())
$oldMode=$env:LONGREACH_BOOT_STUB_MODE
$oldEndpointContext=$global:LongreachAndroidAdbContext
$oldPidFile=$env:LONGREACH_BOOT_STUB_PID
$owner=$null
$control=$null
$global:AndroidBootFixturePwsh=(Get-Command pwsh).Source
$global:AndroidBootFixtureStub=$null
function Start-BootFixtureProcess([string]$Stdout,[string]$Stderr) {
    $options=@{FilePath=$global:AndroidBootFixturePwsh;
        ArgumentList=@('-NoProfile','-File',('"'+$global:AndroidBootFixtureStub+'"'));PassThru=$true}
    if ($IsWindows) { $options.WindowStyle='Hidden' }
    if ($Stdout) { $options.RedirectStandardOutput=$Stdout;$options.RedirectStandardError=$Stderr }
    return Microsoft.PowerShell.Management\Start-Process @options
}
function Start-Process {
    param($FilePath,[string[]]$ArgumentList,$WindowStyle,[switch]$PassThru,$RedirectStandardOutput,$RedirectStandardError)
    if ($FilePath -cne $global:AndroidBootFixtureStub -or
            ($ArgumentList -join '|') -cne '-H|localhost|-P|5037|-s|emulator-5582|shell|getprop|sys.boot_completed') {
        throw 'Unexpected boot-query invocation'
    }
    if ($WindowStyle -ne 'Hidden') { throw 'Boot query did not request a hidden process' }
    # Adapt only the executable boundary. The production helper still owns a
    # real process handle, waits for it, checks its exit status and terminates it.
    return Start-BootFixtureProcess $RedirectStandardOutput $RedirectStandardError
}
function Assert-Ready([bool]$Condition,[string]$Message){if(!$Condition){throw $Message}}
function Expect-ReadyFailure([scriptblock]$Body,[string]$Pattern) {
    try{& $Body}catch{if($_.Exception.Message -notmatch $Pattern){throw};return}
    throw "Expected failure: $Pattern"
}
try {
    New-Item -ItemType Directory -Path $fixture | Out-Null
    Set-AndroidAdbEndpointContext -Directory $fixture -Endpoint (Get-AndroidAdbEndpoint -Environment @{})
    @'
if ($env:LONGREACH_BOOT_STUB_PID) { [IO.File]::WriteAllText($env:LONGREACH_BOOT_STUB_PID,[string]$PID) }
if ($env:LONGREACH_BOOT_STUB_MODE -in @('ready','nonzero')) {
    [Console]::WriteLine('1')
    if ($env:LONGREACH_BOOT_STUB_MODE -eq 'nonzero') { exit 1 }
    exit 0
}
[Threading.Thread]::Sleep([Threading.Timeout]::Infinite)
'@ | Set-Content -LiteralPath "$fixture/adb-stub.ps1" -Encoding utf8
    $stub=(Get-Item -LiteralPath "$fixture/adb-stub.ps1").FullName
    $global:AndroidBootFixtureStub=$stub
    $env:LONGREACH_BOOT_STUB_MODE='hold'
    $env:LONGREACH_BOOT_STUB_PID=''
    $owner=Start-BootFixtureProcess
    $control=Start-BootFixtureProcess
    $options=@{Adb=$stub;EmulatorPid=$owner.Id;TimeoutSeconds=5;QueryTimeoutMilliseconds=2000;PollMilliseconds=10}

    $ready=(New-Item -ItemType Directory "$fixture/ready").FullName
    $env:LONGREACH_BOOT_STUB_MODE='ready'
    Wait-AndroidBoot @options -RunDirectory $ready
    Assert-Ready (Test-Path "$ready/boot-ready.json") 'A successful query was not recorded'

    $nonzero=(New-Item -ItemType Directory "$fixture/nonzero").FullName
    $env:LONGREACH_BOOT_STUB_MODE='nonzero'
    Expect-ReadyFailure {Wait-AndroidBoot @options -RunDirectory $nonzero} 'did not boot within'
    Assert-Ready (!(Test-Path "$nonzero/boot-ready.json")) 'Nonzero client exit was accepted as ready'

    $hung=(New-Item -ItemType Directory "$fixture/hung").FullName
    $env:LONGREACH_BOOT_STUB_MODE='hold'
    $env:LONGREACH_BOOT_STUB_PID="$hung/client.pid"
    $timer=[Diagnostics.Stopwatch]::StartNew()
    Expect-ReadyFailure {Wait-AndroidBoot @options -RunDirectory $hung} 'did not boot within'
    Assert-Ready ($timer.Elapsed.TotalSeconds -lt 9) 'Hung client was not bounded'
    $clientId=[int](Get-Content "$hung/client.pid")
    Assert-Ready (!(Get-Process -Id $clientId -ErrorAction SilentlyContinue)) 'Owned timed-out query survived'
    $control.Refresh()
    Assert-Ready (!$control.HasExited) 'An unrelated control process was stopped'

    $panic=(New-Item -ItemType Directory "$fixture/panic").FullName
    Set-Content "$panic/kernel-shell.log" '[2.0] Kernel panic - not syncing: fixture log'
    $env:LONGREACH_BOOT_STUB_PID="$panic/client.pid"
    Expect-ReadyFailure {Wait-AndroidBoot @options -RunDirectory $panic} 'Guest kernel panic'
    Assert-Ready (!(Test-Path "$panic/client.pid")) 'A query started after a recorded boot panic'

    $exited=(New-Item -ItemType Directory "$fixture/exited").FullName
    Stop-Process -InputObject $owner
    $owner.WaitForExit()
    Expect-ReadyFailure {Wait-AndroidBoot @options -RunDirectory $exited} 'Emulator exited'
    $control.Refresh()
    Assert-Ready (!$control.HasExited) 'An unrelated process was stopped during failure handling'
    Write-Output 'PASS: readiness, nonzero refusal, bounded hung query, panic log, exited guest and unrelated-process preservation'
} finally {
    foreach($process in @($owner,$control)) {
        if($process) {
            if(!$process.HasExited){Stop-Process -InputObject $process -ErrorAction SilentlyContinue;$process.WaitForExit()}
            $process.Dispose()
        }
    }
    $env:LONGREACH_BOOT_STUB_MODE=$oldMode
    Clear-AndroidAdbEndpointContext $fixture
    if ($oldEndpointContext) { $global:LongreachAndroidAdbContext=$oldEndpointContext }
    $env:LONGREACH_BOOT_STUB_PID=$oldPidFile
    Remove-Variable AndroidBootFixturePwsh,AndroidBootFixtureStub -Scope Global -ErrorAction SilentlyContinue
    if(Test-Path -LiteralPath $fixture) {
        $resolved=(Resolve-Path -LiteralPath $fixture).Path
        if([IO.Path]::GetDirectoryName($resolved) -ne $parent -or [IO.Path]::GetFileName($resolved) -notlike 'android-ready-*'){throw 'Unexpected fixture cleanup path'}
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
