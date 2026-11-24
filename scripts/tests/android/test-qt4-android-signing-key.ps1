# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
# First-key initialization and reuse with a recording keytool boundary.
param([string]$RepoRoot=(Resolve-Path "$PSScriptRoot/../../..").Path)
$ErrorActionPreference='Stop'
. "$RepoRoot/scripts/build/qt4-android/host.ps1"
$parent=(New-Item -ItemType Directory -Force "$RepoRoot/build/fixtures").FullName
$fixture=Join-Path $parent ('qt4-signing-key-'+[guid]::NewGuid())
$global:Qt4SigningCalls=0
function Invoke-DonutCommand([string]$Program,[string[]]$Arguments) {
    if ($Program -notlike '*/keytool.exe' -or $Arguments[0] -ne '-genkeypair') { throw 'Unexpected signing fixture command' }
    $global:Qt4SigningCalls++
    $index=[Array]::IndexOf($Arguments,'-keystore')
    [IO.File]::WriteAllText($Arguments[$index+1],'synthetic first signing key')
}
try {
    New-Item -ItemType Directory -Path $fixture | Out-Null
    $key=Initialize-DonutSigningKey $fixture 'recording-jdk/bin'
    if ($global:Qt4SigningCalls -ne 1 -or !(Test-Path -LiteralPath $key)) { throw 'First signing key was not established' }
    $hash=(Get-FileHash -LiteralPath $key).Hash
    if ((Initialize-DonutSigningKey $fixture 'recording-jdk/bin') -cne $key -or $global:Qt4SigningCalls -ne 1) { throw 'Existing key was regenerated' }
    if ((Get-FileHash -LiteralPath $key).Hash -cne $hash) { throw 'Existing signing input changed' }
    Write-Output 'PASS: first Qt4 signing key is established once and reused unchanged'
} finally {
    if (Test-Path -LiteralPath $fixture) {
        $resolved=(Resolve-Path -LiteralPath $fixture).Path
        if ([IO.Path]::GetDirectoryName($resolved) -ne $parent -or [IO.Path]::GetFileName($resolved) -notlike 'qt4-signing-key-*') { throw 'Unexpected fixture cleanup path' }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
    Remove-Variable Qt4SigningCalls -Scope Global -ErrorAction SilentlyContinue
}
