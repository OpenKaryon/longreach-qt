# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
# Actual query process handles/deadlines through a controlled PowerShell adapter.
param([string]$RepoRoot=(Resolve-Path "$PSScriptRoot/../../..").Path)
$ErrorActionPreference='Stop'
. "$RepoRoot/scripts/run/android/android-process-exit.ps1"
$parent=(New-Item -ItemType Directory -Force "$RepoRoot/build/fixtures").FullName
$fixture=Join-Path $parent ('android-exit-query-'+[guid]::NewGuid())
$oldMode=$env:LONGREACH_EXIT_QUERY_MODE
$control=$null
$global:AndroidExitQueryPwsh=(Get-Command pwsh).Source
$global:AndroidExitQueryStub=$null
$global:AndroidExitQueryChildId=0
$global:AndroidExitQueryChildTicks=0
$global:AndroidExitQueryCalls=[Collections.Generic.List[string]]::new()
function Start-Process {
    param($FilePath,[string[]]$ArgumentList,$WindowStyle,[switch]$PassThru,$RedirectStandardOutput,$RedirectStandardError)
    if ($FilePath -cne $global:AndroidExitQueryStub -or $WindowStyle -ne 'Hidden') { throw 'Unexpected query process' }
    $kind=switch ($ArgumentList -join '|') {
        '-s|emulator-5580|logcat|-d|-v|brief' { 'logcat' }
        '-s|emulator-5580|shell|ps' { 'ps' }
        default { throw 'Unexpected query arguments' }
    }
    $global:AndroidExitQueryCalls.Add($kind)
    $options=@{FilePath=$global:AndroidExitQueryPwsh;PassThru=$true;
        ArgumentList=@('-NoLogo','-NoProfile','-NonInteractive','-File',('"'+$global:AndroidExitQueryStub+'"'),'-Kind',$kind);
        RedirectStandardOutput=$RedirectStandardOutput;RedirectStandardError=$RedirectStandardError}
    if ($IsWindows) { $options.WindowStyle='Hidden' }
    $child=Microsoft.PowerShell.Management\Start-Process @options
    $global:AndroidExitQueryChildId=$child.Id
    $global:AndroidExitQueryChildTicks=$child.StartTime.Ticks
    return $child
}
function Expect-QueryFailure([scriptblock]$Body,[string]$Reason) {
    try { & $Body } catch { if ($_.Exception.Message -notmatch $Reason) { throw }; return }
    throw 'Expected query failure'
}
try {
    New-Item -ItemType Directory -Path $fixture | Out-Null
    @'
param([string]$Kind)
if ($env:LONGREACH_EXIT_QUERY_MODE -eq 'hold') { [Threading.Thread]::Sleep([Threading.Timeout]::Infinite) }
if ($env:LONGREACH_EXIT_QUERY_MODE -eq 'nonzero') { [Console]::WriteLine('0');exit 1 }
[Console]::WriteLine('observation-'+$Kind)
'@ | Set-Content "$fixture/query.ps1" -Encoding utf8
    $global:AndroidExitQueryStub=(Get-Item "$fixture/query.ps1").FullName
    $env:LONGREACH_EXIT_QUERY_MODE='hold'
    $start=@{FilePath=$global:AndroidExitQueryPwsh;PassThru=$true;
        ArgumentList=@('-NoProfile','-NonInteractive','-File',('"'+$global:AndroidExitQueryStub+'"'))}
    if ($IsWindows) { $start.WindowStyle='Hidden' }
    $control=Microsoft.PowerShell.Management\Start-Process @start
    $env:LONGREACH_EXIT_QUERY_MODE='ready'
    $snapshot=Get-AndroidProcessObservation $global:AndroidExitQueryStub 'emulator-5580' $fixture 8000
    if (($global:AndroidExitQueryCalls -join '|') -cne 'logcat|ps' -or
            ($snapshot.RawLog -join '') -cne 'observation-logcat' -or ($snapshot.Ps -join '') -cne 'observation-ps') {
        throw 'Exit observations did not run in logcat-then-ps order'
    }
    $env:LONGREACH_EXIT_QUERY_MODE='nonzero'
    Expect-QueryFailure { Invoke-AndroidExitQuery $global:AndroidExitQueryStub 'emulator-5580' @('shell','ps') $fixture 'nonzero' 4000 } 'observation failed'
    $ignored=@(Invoke-AndroidExitQuery $global:AndroidExitQueryStub 'emulator-5580' @('shell','ps') $fixture 'nonzero-poll' 4000 -AllowNonzero)
    if ($ignored.Count -ne 0) { throw 'Nonzero query stdout was accepted as an observation' }
    $env:LONGREACH_EXIT_QUERY_MODE='hold'
    $timer=[Diagnostics.Stopwatch]::StartNew()
    Expect-QueryFailure { Invoke-AndroidExitQuery $global:AndroidExitQueryStub 'emulator-5580' @('shell','ps') $fixture 'hung' 1500 } 'Timed out'
    if ($timer.Elapsed.TotalSeconds -ge 5) { throw 'Owned exit query was not bounded' }
    if (Get-Process -Id $global:AndroidExitQueryChildId -ErrorAction SilentlyContinue) { throw 'Timed-out query survived' }
    $control.Refresh()
    if ($control.HasExited) { throw 'Unrelated control process was stopped' }
    Write-Output 'PASS: actual query ordering, nonzero refusal, bounded timeout and owned-process termination'
} finally {
    $remaining=Get-Process -Id $global:AndroidExitQueryChildId -ErrorAction SilentlyContinue
    if ($remaining -and $remaining.StartTime.Ticks -eq $global:AndroidExitQueryChildTicks) {
        Stop-Process -InputObject $remaining -ErrorAction SilentlyContinue
        $remaining.WaitForExit(3000) | Out-Null
        $remaining.Dispose()
    }
    if ($control) {
        if (!$control.HasExited) { Stop-Process -InputObject $control; $control.WaitForExit(3000) | Out-Null }
        $control.Dispose()
    }
    $env:LONGREACH_EXIT_QUERY_MODE=$oldMode
    Remove-Variable AndroidExitQueryPwsh,AndroidExitQueryStub,AndroidExitQueryChildId,AndroidExitQueryChildTicks,AndroidExitQueryCalls -Scope Global -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $fixture) {
        $resolved=(Resolve-Path -LiteralPath $fixture).Path
        if ([IO.Path]::GetDirectoryName($resolved) -ne $parent -or [IO.Path]::GetFileName($resolved) -notlike 'android-exit-query-*') { throw 'Unexpected fixture cleanup path' }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
