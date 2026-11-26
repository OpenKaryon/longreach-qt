# SPDX-License-Identifier: GPL-3.0-or-later
param([string]$RepoRoot=(Resolve-Path "$PSScriptRoot/../../..").Path)
$ErrorActionPreference='Stop'
. "$RepoRoot/scripts/run/android/android-process-exit.ps1"
$parent=(New-Item -ItemType Directory -Force "$RepoRoot/build/fixtures").FullName
$fixture=Join-Path $parent ('android-log-capture-'+[guid]::NewGuid().ToString('N'))
$global:CaptureFixtureLines=[Collections.Generic.List[string]]::new()
$global:CaptureFixtureStalled=$false
$global:CaptureFixtureReadyDelay=0
$global:CaptureFixtureReadyOverrun=$false
$global:CaptureFixtureReadyPending=0
$global:CaptureFixtureReadyBudgets=[Collections.Generic.List[int]]::new()
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
    } elseif($Command[0] -eq 'shell' -and $Command[1] -eq 'cat'){
        if($Name -eq 'logcat-capture-ready-query'){
            $global:CaptureFixtureReadyBudgets.Add([int]$TimeoutMilliseconds)
            $delay=if($global:CaptureFixtureReadyOverrun){$TimeoutMilliseconds+75}else{$global:CaptureFixtureReadyDelay}
            if($delay -gt $TimeoutMilliseconds -and !$global:CaptureFixtureReadyOverrun){
                Start-Sleep -Milliseconds $TimeoutMilliseconds
                throw 'Recorded readiness query timed out at its supplied budget'
            }
            if($delay -gt 0){Start-Sleep -Milliseconds $delay}
            if($global:CaptureFixtureReadyPending -gt 0){$global:CaptureFixtureReadyPending--;return @()}
        }
        $lines=@($global:CaptureFixtureLines.ToArray())
    }
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
    # These are recorded ADB boundaries, not native process/device calls.
    $global:CaptureFixtureLines.Clear();$global:CaptureFixtureReadyBudgets.Clear()
    $global:CaptureFixtureReadyDelay=1200
    $delayed=New-Item -ItemType Directory -Path "$fixture/ready-delayed"
    $hash=Start-AndroidCaseLogCapture never-executed emulator-5580 $delayed.FullName
    if(!$hash -or $global:CaptureFixtureReadyBudgets.Count -ne 1 -or
       $global:CaptureFixtureReadyBudgets[0] -lt 1200 -or $global:CaptureFixtureReadyBudgets[0] -gt 5000){throw 'Ready read lost its existing five-second window'}

    $global:CaptureFixtureLines.Clear();$global:CaptureFixtureReadyBudgets.Clear()
    $global:CaptureFixtureReadyDelay=250;$global:CaptureFixtureReadyPending=2
    $pending=New-Item -ItemType Directory -Path "$fixture/ready-pending"
    Start-AndroidCaseLogCapture never-executed emulator-5580 $pending.FullName|Out-Null
    $budgets=@($global:CaptureFixtureReadyBudgets.ToArray())
    if($budgets.Count -ne 3 -or $budgets[0] -le $budgets[1] -or $budgets[1] -le $budgets[2] -or
       @($budgets|Where-Object {$_ -le 0 -or $_ -gt 5000}).Count){throw 'Ready polling reset or exceeded its shared deadline'}

    $global:CaptureFixtureLines.Clear();$global:CaptureFixtureReadyBudgets.Clear()
    $global:CaptureFixtureReadyDelay=0;$global:CaptureFixtureReadyOverrun=$true
    $late=New-Item -ItemType Directory -Path "$fixture/ready-late"
    Expect-Failure {Start-AndroidCaseLogCapture never-executed emulator-5580 $late.FullName} 'did not become ready'
    if(Test-Path "$($late.FullName)/logcat-capture.json"){throw 'Late ready value published a success receipt'}

    $global:CaptureFixtureLines.Clear();$global:CaptureFixtureReadyBudgets.Clear()
    $global:CaptureFixtureReadyOverrun=$false;$global:CaptureFixtureStalled=$true
    $missing=New-Item -ItemType Directory -Path "$fixture/ready-missing"
    Expect-Failure {Start-AndroidCaseLogCapture never-executed emulator-5580 $missing.FullName} 'did not become ready'
    if(Test-Path "$($missing.FullName)/logcat-capture.json"){throw 'Missing ready value published a success receipt'}
    Write-Output 'PASS: delayed ready inside unchanged5s, shrinking shared budget, late/missing ready refused'
    Write-Output 'PASS: rotated ring refused, complete capture proves exit, stale writer and late crash refused'
} finally {
    Remove-Variable CaptureFixtureLines,CaptureFixtureStalled,CaptureFixtureReadyDelay,CaptureFixtureReadyOverrun,CaptureFixtureReadyPending,CaptureFixtureReadyBudgets -Scope Global -ErrorAction SilentlyContinue
    if(Test-Path -LiteralPath $fixture){
        $resolved=(Resolve-Path -LiteralPath $fixture).Path
        if([IO.Path]::GetDirectoryName($resolved) -ne $parent -or [IO.Path]::GetFileName($resolved) -notlike 'android-log-capture-*'){throw 'Unexpected fixture cleanup path'}
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
