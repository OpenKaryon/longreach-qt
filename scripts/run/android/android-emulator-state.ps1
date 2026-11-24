# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
# Read-only preflight for the supported archived Windows emulator engines.

function Get-AndroidEmulatorProcessNames {
    param([string]$Emulator)
    # Explicit engine/frontend names, not emulator*: check/crash services alone
    # do not imply an active guest. Retain historical emulator64-x86 callers.
    $names=@('emulator','emulator-arm','emulator-x86','emulator64-x86',
        'emulator-mips','emulator-ranchu-arm64','emulator64-ranchu-arm64',
        'emulator-ranchu-mips64','emulator64-ranchu-mips64',
        'qemu-system-armel','qemu-system-armel-headless',
        'qemu-system-aarch64','qemu-system-aarch64-headless',
        'qemu-system-i386','qemu-system-i386-headless',
        'qemu-system-x86_64','qemu-system-x86_64-headless',
        'qemu-system-mipsel','qemu-system-mips64el')
    if ($Emulator) { $names += [IO.Path]::GetFileNameWithoutExtension($Emulator) }
    @($names | Where-Object { $_ } | Sort-Object -Unique)
}

function Assert-AndroidNoEmulatorRunning {
    param([string]$Emulator,[string]$Message='Another Android emulator is running.')
    $names=@(Get-AndroidEmulatorProcessNames -Emulator $Emulator)
    # Get-Process accepts wildcard patterns. Treat a custom executable basename
    # literally, including legal filename characters such as square brackets.
    $patterns=@($names | ForEach-Object { [Management.Automation.WildcardPattern]::Escape($_) })
    if (Get-Process -Name $patterns -ErrorAction SilentlyContinue) { throw $Message }
}
