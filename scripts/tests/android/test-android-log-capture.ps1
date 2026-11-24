# SPDX-License-Identifier: GPL-3.0-or-later
param([string]$RepoRoot=(Resolve-Path "$PSScriptRoot/../../..").Path)
$ErrorActionPreference='Stop'
. "$RepoRoot/scripts/run/android/android-process-exit.ps1"
$parent=(New-Item -ItemType Directory -Force "$RepoRoot/build/fixtures").FullName
$fixture=Join-Path $parent ('android-log-capture-'+[guid]::NewGuid().ToString('N'))
$global:CaptureFixtureLines=[Collections.Generic.List[string]]::new()
$global:CaptureFixtureStalled=$false
function Start-Process { throw 'Native process launch forbidden in this fixture' }
function Start-AndroidOwnedLogCapture {
    param($Directory,$Adb,$Serial,$RemoteFile)
    if($Serial -ne 'emulator-5580' -or $RemoteFile -notmatch '^/data/local/longreach-log-[0-9a-f]{32}\.log$'){throw 'Unexpected capture transport'}
    return @{log_capture_request_sha256=('c'*64);log_capture_owner_sha256=('d'*64)}
}
function Invoke-AndroidExitQuery {
    param($Adb,$Serial,[string[]]$Command,$Directory,$Name,$TimeoutMilliseconds,[switch]$AllowNonzero)
    $lines=@()
    if($Command[0] -eq 'shell' -and $Command[1] -eq 'log') {
        if(!$global:CaptureFixtureStalled){$global:CaptureFixtureLines.Add('I/LongreachCapture( 321): '+$Command[-1])}
    } elseif($Command[0] -eq 'shell' -and $Command[1] -eq 'cat'){$lines=@($global:CaptureFixtureLines.ToArray())}
    elseif($Command[0] -eq 'shell' -and $Command[1] -eq 'ps'){$lines=@('USER PID PPID NAME','root 1 0 /init')}
    elseif($Command[0] -eq 'logcat'){$lines=@($global:CaptureFixtureLines.ToArray() | Select-Object -Last 100)}
    else {throw 'Unexpected capture query'}
    $lines | Set-Content -LiteralPath "$Directory/$Name.stdout" -Encoding utf8
    return $lines
}
function Expect-Failure([scriptblock]$Body,[string]$Message) {
    try { & $Body } catch {if($_.Exception.Message -notmatch $Message){throw};return}
    throw 'Expected log-capture refusal'
}
try {
    New-Item -ItemType Directory $fixture | Out-Null
    $hash=Start-AndroidCaseLogCapture never-executed emulator-5580 $fixture
    @{log_capture_sha256=$hash} | ConvertTo-Json | Set-Content "$fixture/input-receipt.json"
    $marker='BEGIN-0123456789abcdef0123456789abcdef'
    $package='org.longreachqt.examples.quickqmlgallery'
    $global:CaptureFixtureLines.Add("I/LongreachCase( 321): $marker")
    $global:CaptureFixtureLines.Add("I/ActivityManager( 68): Start proc $package for activity: pid=42 uid=10001")
    for($i=0;$i -lt 2000;$i++){$global:CaptureFixtureLines.Add('E/libEGL( 42): no more slots for eglGetProcAddress')}
    $global:CaptureFixtureLines.Add('I/LongreachExamples( 42): Example returned 0')
    $global:CaptureFixtureLines.Add("I/ActivityManager( 68): Process $package (pid 42) has died.")
    $ring=@(Invoke-AndroidExitQuery never-executed emulator-5580 @('logcat','-d') $fixture ring 1000)
    Expect-Failure {Get-AndroidApi21CaseLog $ring $marker} 'exactly one'
    $proof=Wait-AndroidApplicationExit -Adb never-executed -Serial emulator-5580 -Directory $fixture -Package $package -Marker $marker -TimeoutSeconds 5 -PollMilliseconds 1
    if(!$proof.process_exit_confirmed -or !$proof.log_capture_observation_sha256){throw 'Full capture did not bind process exit'}
    $global:CaptureFixtureStalled=$true
    Expect-Failure {Get-AndroidCaseRawLog never-executed emulator-5580 $fixture stalled 100} 'freshness deadline'
    $global:CaptureFixtureStalled=$false
    $global:CaptureFixtureLines.Add('F/libc( 42): Fatal signal 11')
    Expect-Failure {Wait-AndroidApplicationExit -Adb never-executed -Serial emulator-5580 -Directory $fixture -Package $package -Marker $marker -TimeoutSeconds 5 -PollMilliseconds 1} 'Fatal cleanup error'
    if(Test-Path "$fixture/process-exit.json"){throw 'Late fatal capture retained old success'}
    '{}' | Set-Content "$fixture/logcat-capture.json"
    Expect-Failure {Get-AndroidCaseRawLog never-executed emulator-5580 $fixture changed 100} 'differs from its case receipt'
    Write-Output 'PASS: rotated ring refused, complete capture proves exit, stale writer and late crash refused'
} finally {
    Remove-Variable CaptureFixtureLines,CaptureFixtureStalled -Scope Global -ErrorAction SilentlyContinue
    if(Test-Path -LiteralPath $fixture){
        $resolved=(Resolve-Path -LiteralPath $fixture).Path
        if([IO.Path]::GetDirectoryName($resolved) -ne $parent -or [IO.Path]::GetFileName($resolved) -notlike 'android-log-capture-*'){throw 'Unexpected fixture cleanup path'}
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
