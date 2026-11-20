# SPDX-License-Identifier: GPL-3.0-or-later
<# Exercise real child timeouts and boot-log failures without an emulator. #>
param([string]$RepoRoot=(Resolve-Path "$PSScriptRoot/../..").Path)
$ErrorActionPreference='Stop'
. "$RepoRoot/scripts/run/android-wait-boot.ps1"
$parent=(New-Item -ItemType Directory -Force "$RepoRoot/build/fixtures").FullName
$fixture=Join-Path $parent ('android-ready-'+[guid]::NewGuid())
$oldMode=$env:LONGREACH_BOOT_STUB_MODE
$oldPidFile=$env:LONGREACH_BOOT_STUB_PID
$owner=$null
$control=$null
function Assert-Ready([bool]$Condition,[string]$Message){if(!$Condition){throw $Message}}
function Expect-ReadyFailure([scriptblock]$Body,[string]$Pattern) {
    try{& $Body}catch{if($_.Exception.Message -notmatch $Pattern){throw};return}
    throw "Expected failure: $Pattern"
}
try {
    New-Item -ItemType Directory -Path $fixture | Out-Null
    $source='using System; using System.Diagnostics; using System.IO; using System.Threading; class BootStub { static int Main() { string p=Environment.GetEnvironmentVariable("LONGREACH_BOOT_STUB_PID"); if(!String.IsNullOrEmpty(p)) File.WriteAllText(p,Process.GetCurrentProcess().Id.ToString()); string m=Environment.GetEnvironmentVariable("LONGREACH_BOOT_STUB_MODE"); if(m=="ready" || m=="nonzero") { Console.WriteLine("1"); return m=="ready"?0:1; } Thread.Sleep(Timeout.Infinite); return 0; } }'
    Set-Content -LiteralPath "$fixture/adb-stub.cs" -Value $source
    $sourcePath=(Get-Item -LiteralPath "$fixture/adb-stub.cs").FullName
    $stub=Join-Path $fixture 'adb-stub.exe'
    Write-Output "Compiling local fixture: $sourcePath"
    & "$env:WINDIR/Microsoft.NET/Framework64/v4.0.30319/csc.exe" /nologo /target:exe "/out:$stub" $sourcePath
    if($LASTEXITCODE){throw 'Could not compile the local process fixture'}
    $stub="$fixture/adb-stub.exe"
    $env:LONGREACH_BOOT_STUB_MODE='hold'
    $env:LONGREACH_BOOT_STUB_PID=''
    $owner=Start-Process -FilePath $stub -WindowStyle Hidden -PassThru
    $control=Start-Process -FilePath $stub -WindowStyle Hidden -PassThru
    $options=@{Adb=$stub;EmulatorPid=$owner.Id;TimeoutSeconds=1;QueryTimeoutMilliseconds=100;PollMilliseconds=10}

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
    Assert-Ready ($timer.Elapsed.TotalSeconds -lt 5) 'Hung client was not bounded'
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
    $env:LONGREACH_BOOT_STUB_PID=$oldPidFile
    if(Test-Path -LiteralPath $fixture) {
        $resolved=(Resolve-Path -LiteralPath $fixture).Path
        if([IO.Path]::GetDirectoryName($resolved) -ne $parent -or [IO.Path]::GetFileName($resolved) -notlike 'android-ready-*'){throw 'Unexpected fixture cleanup path'}
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
