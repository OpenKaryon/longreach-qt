# SPDX-License-Identifier: GPL-3.0-or-later
<# Ordinary case ownership/history fixtures; no tools, ADB or guests. #>
param([string]$RepoRoot=(Resolve-Path "$PSScriptRoot/../../..").Path)
$ErrorActionPreference='Stop'
. "$RepoRoot/scripts/build/android-api21/artifact-lock.ps1"
. "$RepoRoot/scripts/run/android/android-case-state.ps1"
$parent=(New-Item -ItemType Directory -Force "$RepoRoot/build/fixtures").FullName
$fixture=Join-Path $parent ('android-case-state-'+[guid]::NewGuid())
$caseLock=$null
function Assert-Case([bool]$Condition,[string]$Message) { if (!$Condition) { throw $Message } }
function Expect-CaseFailure([scriptblock]$Action,[string]$Message) {
    try { & $Action } catch { Assert-Case ($_.Exception.Message -match $Message) "Unexpected case failure: $_"; return }
    throw 'Expected case state refusal'
}
try {
    $assets=(New-Item -ItemType Directory -Force "$fixture/assets/apk/extended").Parent.Parent.FullName
    $apk=Join-Path $assets 'apk/extended/qt-selftest.apk'
    [IO.File]::WriteAllText($apk,'APK source bytes')
    $case=(New-Item -ItemType Directory -Force "$assets/run/strict-cxx23").FullName
    $roots=Get-AndroidApi10CaseRoots -Apk $apk -Directory $case
    Assert-Case (Test-AndroidCasePathEqual $roots.Root $assets) 'Extended APK lost its artifact root'
    $batch=Join-Path $assets 'run/batch-receipt.json'
    $roots=Get-AndroidApi10CaseRoots -Apk $apk -Directory $case -BatchReceipt $batch -CaseName strict-cxx23
    Assert-Case (Test-AndroidCasePathEqual $roots.Root $assets) 'Batch root inference changed'
    Expect-CaseFailure { Get-AndroidApi10CaseRoots -Apk $apk -Directory $assets } 'must not contain'
    Expect-CaseFailure { Get-AndroidApi10CaseRoots -Apk $apk -Directory "$assets/run/other" -BatchReceipt $batch -CaseName strict-cxx23 } 'does not match'
    Expect-CaseFailure { Get-AndroidApi10CaseRoots -Apk $apk -Directory $case -BatchReceipt $batch -CaseName strict-cxx23 -ArtifactRoot $fixture } 'differs'
    [IO.File]::WriteAllText("$fixture/not-a-directory",'preserved input')
    Expect-CaseFailure { Get-AndroidApi10CaseRoots -Apk $apk -Directory "$fixture/not-a-directory" } 'ordinary directory'
    Assert-AndroidCaseInputsSeparate $case @('')
    Expect-CaseFailure { Assert-AndroidCaseInputsSeparate $case @("$case/source.apk") } 'protected'
    $caseLock=Enter-AndroidArtifactLock $case
    $oldHistory=(New-Item -ItemType Directory -Force (Join-Path $case ('previous-'+('d'*32)))).FullName
    [IO.File]::WriteAllText("$oldHistory/old.txt",'older immutable attempt')
    $old=@{
        'files/suite.log'='retained stdout';'input-receipt.json'='retained receipt';
        'logcat-raw.log'='retained raw log';'logcat.log'='retained scoped log';
        'process-exit.json'='retained exit proof';'guest-cpu-baseline.json'='retained CPU receipt';
        'emulator.stdout'='retained emulator stdout';'emulator.stderr'='retained emulator stderr';
        'userdata-qemu.img'='retained userdata';'guest.txt'='retained properties';
        'previous-scratch/log.txt'='ordinary prior-attempt directory'
    }
    foreach ($name in $old.Keys) {
        $path=Join-Path $case $name
        New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
        [IO.File]::WriteAllText($path,$old[$name])
    }
    $first=Start-AndroidCaseAttempt $case
    Assert-Case (Test-Path -LiteralPath $first.Pending) 'New case has no pending attempt'
    Assert-Case ([IO.File]::ReadAllText("$oldHistory/old.txt") -ceq 'older immutable attempt') 'Prior history was changed'
    foreach ($name in $old.Keys) {
        Assert-Case ([IO.File]::ReadAllText((Join-Path $first.History $name)) -ceq $old[$name]) "Case history lost $name"
        Assert-Case (!(Test-Path -LiteralPath (Join-Path $case $name))) "Old case data remained active: $name"
    }
    Write-AndroidCaseReceipt $case @{completed=$false;case_attempt_id=$first.Id}
    $script:CaseMoves=0
    function Move-Item {
        param([string]$LiteralPath,[string]$Destination)
        $script:CaseMoves++
        if ($script:CaseMoves -eq 2) { throw 'fixture archive interruption' }
        Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination
    }
    Expect-CaseFailure { Start-AndroidCaseAttempt $case } 'fixture archive interruption'
    Remove-Item Function:Move-Item
    Assert-Case (@(Get-ChildItem -LiteralPath $case -Filter 'attempt-*.pending.json').Count -ge 1) 'Interrupted archive lost its incomplete state'
    $third=Start-AndroidCaseAttempt $case
    Assert-Case (@(Get-ChildItem -LiteralPath $case -Filter 'attempt-*.pending.json').Count -eq 1) 'Recovery mixed old pending attempts into the active case'
    Assert-Case (Test-Path -LiteralPath $third.Pending) 'Recovery did not retain its own pending attempt'
    foreach ($name in $old.Keys) {
        Assert-Case ([IO.File]::ReadAllText((Join-Path $first.History $name)) -ceq $old[$name]) "Recovery changed the first saved attempt: $name"
    }
    Write-AndroidCaseReceipt $case @{completed=$true;case_attempt_id=$third.Id}
    Assert-Case ((Get-Content "$case/input-receipt.json" -Raw | ConvertFrom-Json).case_attempt_id -ceq $third.Id) 'Atomic receipt publication failed'
    Assert-Case (@(Get-ChildItem -LiteralPath $case -Filter 'input-receipt.json.*.tmp').Count -eq 0) 'Receipt publication left a temporary file'
    [IO.File]::Delete($third.Pending)
    if ($IsWindows) {
        Assert-Case ($null -eq (Enter-AndroidArtifactLock $case.ToUpperInvariant())) 'Windows path alias did not reuse its parent lease'
    } else {
        $upper=Join-Path $fixture 'CaseSensitive'
        $lower=Join-Path $fixture 'casesensitive'
        $left=Enter-AndroidArtifactLock $upper
        $right=$null
        try {
            $right=Enter-AndroidArtifactLock $lower
            Assert-Case ($left -and $right) 'Distinct Unix paths shared one process-local lease key'
        } finally { if ($right) { $right.Dispose() }; $left.Dispose() }
    }
    Write-Output 'PASS: case roots/input separation, full immutable history, interrupted archive recovery, atomic receipts and lease path semantics'
} finally {
    Remove-Item Function:Move-Item -ErrorAction SilentlyContinue
    if ($caseLock) { $caseLock.Dispose() }
    if (Test-Path -LiteralPath $fixture) {
        $resolved=(Resolve-Path -LiteralPath $fixture).Path
        if ([IO.Path]::GetDirectoryName($resolved) -ne $parent -or [IO.Path]::GetFileName($resolved) -notlike 'android-case-state-*') { throw 'Unexpected case fixture cleanup path' }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
