# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
# Process-name recording only. No actual process enumeration or launch.
param([string]$RepoRoot=(Resolve-Path "$PSScriptRoot/../..").Path)
$ErrorActionPreference='Stop'
. "$RepoRoot/scripts/run/android-emulator-state.ps1"
$global:AndroidEmulatorStateFixture=@{Running=@();Queries=[Collections.Generic.List[object]]::new()}
function Get-Process {
    param([string[]]$Name,$ErrorAction)
    $global:AndroidEmulatorStateFixture.Queries.Add(@($Name))
    if ($ErrorAction -ne 'SilentlyContinue') { throw 'Unexpected process query policy' }
    foreach ($process in $global:AndroidEmulatorStateFixture.Running) {
        if (@($Name | Where-Object { $process -like $_ }).Count) { [pscustomobject]@{Name=$process} }
    }
}
function Stop-Process { throw 'The read-only preflight tried to stop a process' }
function Start-Process { throw 'The read-only preflight tried to start a process' }
try {
    $expected=@('emulator','emulator-arm','emulator-x86','emulator64-x86','emulator-mips',
        'emulator-ranchu-arm64','emulator64-ranchu-arm64','emulator-ranchu-mips64','emulator64-ranchu-mips64',
        'qemu-system-armel','qemu-system-armel-headless','qemu-system-aarch64','qemu-system-aarch64-headless',
        'qemu-system-i386','qemu-system-i386-headless','qemu-system-x86_64','qemu-system-x86_64-headless',
        'qemu-system-mipsel','qemu-system-mips64el')
    $actual=@(Get-AndroidEmulatorProcessNames)
    if ($actual.Count -ne 19 -or @(Compare-Object ($expected | Sort-Object) $actual).Count) { throw 'Incomplete archived emulator-name policy' }
    foreach ($name in $expected) {
        $global:AndroidEmulatorStateFixture.Running=@($name)
        $global:AndroidEmulatorStateFixture.Queries.Clear()
        $message=$null
        try { Assert-AndroidNoEmulatorRunning -Message 'fixture busy engine' } catch { $message=$_.Exception.Message }
        if ($message -cne 'fixture busy engine') { throw "Missed running engine: $name ($message)" }
        if ($global:AndroidEmulatorStateFixture.Queries.Count -ne 1) { throw 'Expected one bounded-name process query' }
    }
    foreach ($name in @('emulator-check','emulator-crash-service','emulator64-crash-service','unrelated-tool')) {
        $global:AndroidEmulatorStateFixture.Running=@($name)
        if (@(Assert-AndroidNoEmulatorRunning).Count) { throw 'Preflight emitted unrelated output' }
    }
    $custom=Join-Path $RepoRoot 'build/custom emulator [one].exe'
    $global:AndroidEmulatorStateFixture.Running=@('custom emulator [one]')
    $message=$null
    try { Assert-AndroidNoEmulatorRunning -Emulator $custom } catch { $message=$_.Exception.Message }
    if ($message -cne 'Another Android emulator is running.') { throw 'Missed literal custom frontend basename' }
    $global:AndroidEmulatorStateFixture.Running=@('custom emulator o')
    Assert-AndroidNoEmulatorRunning -Emulator $custom
    if (@(Get-AndroidEmulatorProcessNames -Emulator (Join-Path $RepoRoot 'emulator.exe')).Count -ne 19) { throw 'Stock custom basename was duplicated' }
    $global:AndroidEmulatorStateFixture.Running=@()
    Assert-AndroidNoEmulatorRunning
    Write-Output 'PASS: 19 exact engine names, helper-only idle states, literal custom names, no process start/stop'
} finally {
    Remove-Variable AndroidEmulatorStateFixture -Scope Global -ErrorAction SilentlyContinue
}
