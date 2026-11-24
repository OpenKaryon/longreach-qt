# SPDX-License-Identifier: GPL-3.0-or-later
# Real bounded Python clients through recording ADB launch boundary. No ADB runs.
param([string]$RepoRoot=(Resolve-Path "$PSScriptRoot/../..").Path)
$ErrorActionPreference='Stop'
. "$RepoRoot/scripts/run/android-api21-adb.ps1"
. "$RepoRoot/scripts/run/android-case-state.ps1"
. "$RepoRoot/scripts/run/android-wait-boot.ps1"
$parent=(New-Item -ItemType Directory -Force "$RepoRoot/build/fixtures").FullName
$fixture=Join-Path $parent ('android-adb-'+[guid]::NewGuid())
$global:AdbFixturePython=(Get-Command python -CommandType Application | Select-Object -First 1).Source
$global:AdbFixtureStart=(Get-Command Start-AndroidAdbClientProcess).ScriptBlock
$global:AdbFixtureMode='args'
$global:AdbFixtureRoot=$fixture
$global:AdbFixtureClientId=0
$global:AdbFixtureClientBirth=''
$global:AdbFixtureCalls=[Collections.Generic.List[object]]::new()
$control=$null;$pipeChild=$null
function Assert-Adb([bool]$Condition,[string]$Message) { if (!$Condition) { throw $Message } }
function Refuse-Adb([scriptblock]$Action,[string]$Pattern) {
    try { & $Action | Out-Null } catch { Assert-Adb ($_.Exception.Message -match $Pattern) "Unexpected ADB failure: $_";return }
    throw 'Expected ADB command refusal'
}
function Start-AndroidAdbClientProcess {
    param($Adb,[string[]]$Arguments)
    $global:AdbFixtureCalls.Add(@{program=$Adb;arguments=@($Arguments)})
    $process=& $global:AdbFixtureStart -Adb $global:AdbFixturePython -Arguments (@('-X','utf8','-u',"$global:AdbFixtureRoot/client with spaces.py",$global:AdbFixtureMode,'--')+$Arguments)
    $global:AdbFixtureClientId=$process.Id
    $global:AdbFixtureClientBirth=$process.StartTime.ToUniversalTime().ToFileTimeUtc().ToString()
    return $process
}
function Stop-AdbFixtureHandle($Process) {
    if ($Process -and !$Process.HasExited) {
        try { $Process.Kill() } catch { if (!$Process.WaitForExit(1000)) { throw } }
        Assert-Adb ($Process.WaitForExit(3000)) 'Fixture child did not stop'
    }
}
try {
    New-Item -ItemType Directory -Path $fixture | Out-Null
    @'
import importlib.util,json,os,pathlib,subprocess,sys,time
mode,arguments=sys.argv[1],sys.argv[3:]
if mode=='hold':
    print('partial before timeout',flush=True)
    time.sleep(30)
elif mode=='pipe':
    core,marker=arguments
    code="import importlib.util,os,pathlib,sys,time; spec=importlib.util.spec_from_file_location('owned',sys.argv[1]); owned=importlib.util.module_from_spec(spec); spec.loader.exec_module(owned); owned.write(pathlib.Path(sys.argv[2]),dict(pid=os.getpid(),creation=owned.process_creation_time(os.getpid()))); time.sleep(30)"
    subprocess.Popen([sys.executable,'-X','utf8','-c',code,core,marker],stdout=sys.stdout,stderr=sys.stderr,creationflags=0x08000000)
    print('parent returned, inherited pipe still open',flush=True)
elif mode=='nonzero':
    print('0',flush=True)
    print('fixture failure details',file=sys.stderr,flush=True)
    sys.exit(7)
elif mode=='burst':
    print('O'*200000)
    print('E'*200000,file=sys.stderr)
elif mode.startswith('power'):
    if 'dumpsys' in arguments:
        print('mStayOnConditions='+('1' if mode=='power-bad' else '3'))
else:
    print(json.dumps(arguments,ensure_ascii=False))
    print('stderr warning is not a result',file=sys.stderr)
'@ | Set-Content "$fixture/client with spaces.py"
    $arguments=@('-s','emulator-5580','push','two words','embedded"quote','trailing\','кириллица')
    $text=Invoke-AndroidAdb -Adb data-only-adb.exe -Arguments $arguments -TimeoutMilliseconds 5000
    Assert-Adb ((($text -join "`n" | ConvertFrom-Json) -join [char]0) -ceq ($arguments -join [char]0)) 'Bounded client changed Windows arguments or mixed stderr'
    $text=Invoke-AndroidApi21Adb -Adb data-only-adb.exe -Serial emulator-5582 -Parameters @('shell','getprop') -TimeoutMilliseconds 5000
    Assert-Adb ((($text | ConvertFrom-Json) -join '|') -ceq '-s|emulator-5582|shell|getprop') 'API21 facade lost its serial or command'
    Invoke-AndroidTool "$fixture/adb.exe" @('start-server') | Out-Null
    Assert-Adb ($global:AdbFixtureCalls[-1].program -ceq "$fixture/adb.exe") 'Raw API10 facade skipped the bounded launch boundary'
    Assert-Adb ((Get-AndroidAdbTimeoutMilliseconds @('-s','serial','push','apk','remote')) -eq 180000) 'Transfer deadline was too short'
    Assert-Adb ((Get-AndroidAdbTimeoutMilliseconds @('-s','serial','shell','pm','install','apk')) -eq 180000) 'Legacy pm install did not receive transfer deadline'
    Assert-Adb ((Get-AndroidAdbTimeoutMilliseconds @('shell','am','start')) -eq 30000) 'Activity deadline policy changed'
    Assert-Adb ((Get-AndroidAdbTimeoutMilliseconds @('-s','serial','logcat','-d')) -eq 15000) 'Ordinary query deadline policy changed'
    $global:AdbFixtureMode='burst'
    $large=@(Invoke-AndroidAdb -Adb data-only-adb.exe -Arguments @('logcat','-d') -TimeoutMilliseconds 5000)
    Assert-Adb ($large.Count -eq 1 -and $large[0].Length -eq 200000 -and $large[0][0] -ceq 'O') 'Large concurrent stdout/stderr blocked or got mixed'
    $global:AdbFixtureMode='nonzero'
    Refuse-Adb { Invoke-AndroidAdb -Adb data-only-adb.exe -Arguments @('shell','cat','result') -TimeoutMilliseconds 5000 } 'adb failed with code 7.*fixture failure details'
    $failed=@(Invoke-AndroidAdb -Adb data-only-adb.exe -Arguments @('shell','cat','result') -TimeoutMilliseconds 5000 -AllowNonzero)
    Assert-Adb ($failed.Count -eq 0 -and $global:LASTEXITCODE -eq 7) 'Nonzero result poll converted stdout zero to completion'
    $control=& $global:AdbFixtureStart -Adb $global:AdbFixturePython -Arguments @('-c','import time; time.sleep(30)')
    $global:AdbFixtureMode='hold'
    $timer=[Diagnostics.Stopwatch]::StartNew()
    Refuse-Adb { Invoke-AndroidAdb -Adb data-only-adb.exe -Arguments @('shell','getprop') -TimeoutMilliseconds 400 } 'ADB command timed out'
    Assert-Adb ($timer.ElapsedMilliseconds -lt 3000) 'ADB wait was not bounded'
    $remaining=$null
    try {
        try { $remaining=[Diagnostics.Process]::GetProcessById($global:AdbFixtureClientId) } catch [ArgumentException] { }
        if ($remaining) {
            $null=$remaining.Handle
            Assert-Adb ($remaining.StartTime.ToUniversalTime().ToFileTimeUtc().ToString() -cne $global:AdbFixtureClientBirth -or $remaining.HasExited) 'Timed-out ADB client survived'
        }
    } finally { if ($remaining) { $remaining.Dispose() } }
    Assert-Adb (!$control.HasExited) 'Timeout stopped the unrelated control process'
    if ($IsWindows) {
        $global:AdbFixtureMode='pipe'
        Refuse-Adb { Invoke-AndroidAdb -Adb data-only-adb.exe -Arguments @("$RepoRoot/scripts/run/android-owned-process.py","$fixture/pipe-child.json") -TimeoutMilliseconds 1500 } 'output did not close'
        $child=Get-Content "$fixture/pipe-child.json" -Raw | ConvertFrom-Json
        $pipeChild=[Diagnostics.Process]::GetProcessById([int]$child.pid)
        $null=$pipeChild.Handle
        Assert-Adb ($pipeChild.StartTime.ToUniversalTime().ToFileTimeUtc().ToString() -ceq $child.creation) 'Pipe child identity changed'
        Assert-Adb (!$pipeChild.HasExited) 'Client timeout killed the external pipe holder'
        Stop-AdbFixtureHandle $pipeChild
    }
    $global:AdbFixtureMode='power'
    Set-AndroidGuestStayAwake -Adb data-only-adb.exe -Serial emulator-5580 -RunDirectory $fixture
    $global:AdbFixtureMode='power-bad'
    Refuse-Adb { Set-AndroidGuestStayAwake -Adb data-only-adb.exe -Serial emulator-5580 -RunDirectory $fixture } 'did not confirm stay-awake'
    Assert-Adb (!$control.HasExited) 'A completed client touched the unrelated control process'
    Write-Output 'PASS: bounded real clients, exact argv/serial, concurrent stdout/stderr, nonzero polls, inherited-pipe deadline, raw/API21/power routing and unrelated process preservation'
} finally {
    if (!$pipeChild -and (Test-Path "$fixture/pipe-child.json")) {
        $child=Get-Content "$fixture/pipe-child.json" -Raw | ConvertFrom-Json
        try {
            $candidate=[Diagnostics.Process]::GetProcessById([int]$child.pid)
            $null=$candidate.Handle
            if ($candidate.StartTime.ToUniversalTime().ToFileTimeUtc().ToString() -ceq $child.creation) { $pipeChild=$candidate } else { $candidate.Dispose() }
        } catch [ArgumentException] { }
    }
    foreach ($process in @($pipeChild,$control)) { if ($process) { try { Stop-AdbFixtureHandle $process } finally { $process.Dispose() } } }
    Remove-Variable AdbFixturePython,AdbFixtureStart,AdbFixtureMode,AdbFixtureRoot,AdbFixtureClientId,AdbFixtureClientBirth,AdbFixtureCalls -Scope Global -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $fixture) {
        $resolved=(Resolve-Path -LiteralPath $fixture).Path
        if ([IO.Path]::GetDirectoryName($resolved) -ne $parent -or [IO.Path]::GetFileName($resolved) -notlike 'android-adb-*') { throw 'Unexpected ADB fixture cleanup path' }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
