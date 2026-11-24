# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
# Native return-zero is insufficient: exercise the real exit state machine on logs/ps.
param([string]$RepoRoot=(Resolve-Path "$PSScriptRoot/../../..").Path)
$ErrorActionPreference='Stop'
. "$RepoRoot/scripts/run/android/android-process-exit.ps1"
$parent=(New-Item -ItemType Directory -Force "$RepoRoot/build/fixtures").FullName
$fixture=Join-Path $parent ('android-process-exit-'+[guid]::NewGuid())
$package='org.longreachqt.examples.qtselftest'
$marker='BEGIN-0123456789abcdef0123456789abcdef'
$start="I/ActivityManager( 100): Start proc $package for activity $package/.SmokeActivity: pid=42 uid=10001"
$death="I/ActivityManager( 100): Process $package (pid 42) has died."
$global:AndroidExitFrames=@()
$global:AndroidExitIndex=0
function Start-Process { throw 'Native process launch forbidden in this fixture' }
function Get-AndroidProcessObservation {
    param($Adb,$Serial,$Directory,$TimeoutMilliseconds)
    $index=[Math]::Min($global:AndroidExitIndex,$global:AndroidExitFrames.Count-1)
    $global:AndroidExitIndex++
    return $global:AndroidExitFrames[$index]
}
function Frame([string[]]$Lines,[switch]$Alive) {
    $ps=@('USER PID PPID NAME','root 1 0 /init')
    if ($Alive) { $ps+='app 42 1 '+$package }
    return [pscustomobject]@{RawLog=@("I/LongreachCase( 100): $marker")+$Lines;Ps=$ps}
}
function Expect-ExitFailure([scriptblock]$Body,[string]$Message) {
    try { & $Body } catch { if ($_.Exception.Message -notmatch $Message) { throw }; return }
    throw 'Expected process-exit failure'
}
try {
    New-Item -ItemType Directory -Path $fixture | Out-Null
    $marker | Set-Content "$fixture/log-marker.txt"
    New-Item -ItemType Directory "$fixture/files" | Out-Null
    '0' | Set-Content "$fixture/files/selftest-result.txt"
    $options=@{Adb='never-executed';Serial='emulator-5580';Directory=$fixture;Package=$package;Marker=$marker;TimeoutSeconds=1;PollMilliseconds=5}
    foreach ($birth in @($start,"I/ActivityManager( 100): Start proc 42:$package/u0a1 for activity")) {
        $global:AndroidExitFrames=@((Frame @($birth,'I/LongreachExamples( 42): Example returned 0',$death)))
        $global:AndroidExitIndex=0
        $proof=Wait-AndroidApplicationExit @options
        if (!$proof.process_exit_confirmed -or $proof.process_id -ne 42 -or $proof.observations -lt 2) { throw 'Exit confirmation was not bound to PID42' }
    }
    # A zero marker and even a death line cannot excuse a process still present.
    $global:AndroidExitFrames=@((Frame @($start,$death) -Alive))
    $global:AndroidExitIndex=0
    Expect-ExitFailure { Wait-AndroidApplicationExit @options } 'exit was not confirmed'
    if (Test-Path "$fixture/process-exit.json") { throw 'Previous exit proof survived a hung teardown' }
    foreach ($lines in @(@($start,$death.Replace('pid 42','pid 99')), @($death,$start))) {
        $global:AndroidExitFrames=@((Frame $lines))
        $global:AndroidExitIndex=0
        Expect-ExitFailure { Wait-AndroidApplicationExit @options } 'exit was not confirmed'
    }
    foreach ($failure in @('F/DEBUG( 42): *** *** *** ***',"F/DEBUG( 42): pid: 42 >>> $package <<<",'F/libc( 42): Fatal signal 11')) {
        $global:AndroidExitFrames=@((Frame @($start,$death)),(Frame @($start,$death,$failure)))
        $global:AndroidExitIndex=0
        Expect-ExitFailure { Wait-AndroidApplicationExit @options } 'Fatal cleanup error'
        if (Test-Path "$fixture/process-exit.json") { throw 'Late fatal record was accepted as teardown success' }
    }
    foreach ($control in @("I/ActivityManager( 100): Force stopping package $package uid=10001",
                           "I/ActivityManager( 100): Killing 42:$package/u0a1: cleanup")) {
        $global:AndroidExitFrames=@((Frame @($start,$control,$death)))
        $global:AndroidExitIndex=0
        Expect-ExitFailure { Wait-AndroidApplicationExit @options } 'killed or force-stopped'
    }
    foreach ($ps in @(@(),@('USER PID PPID NAME'),@('adb: closed'))) {
        Expect-ExitFailure { Test-AndroidApplicationPresent $ps $package 42 } 'ps'
    }
    $global:AndroidExitFrames=@((Frame @($start,$start,$death)))
    $global:AndroidExitIndex=0
    Expect-ExitFailure { Wait-AndroidApplicationExit @options } 'Ambiguous application process launch'
    Write-Output 'PASS: PID-bound exit, live-process timeout, stale death refusal, late crash and forced-stop rejection'
} finally {
    Remove-Variable AndroidExitFrames,AndroidExitIndex -Scope Global -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $fixture) {
        $resolved=(Resolve-Path -LiteralPath $fixture).Path
        if ([IO.Path]::GetDirectoryName($resolved) -ne $parent -or [IO.Path]::GetFileName($resolved) -notlike 'android-process-exit-*') { throw 'Unexpected fixture cleanup path' }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
