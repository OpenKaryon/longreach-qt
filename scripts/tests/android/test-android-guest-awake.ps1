# SPDX-License-Identifier: GPL-3.0-or-later
param([string]$RepoRoot=(Resolve-Path "$PSScriptRoot/../../..").Path)
$ErrorActionPreference='Stop'
. "$RepoRoot/scripts/run/android/android-wait-boot.ps1"
$parent=(New-Item -ItemType Directory -Force "$RepoRoot/build/fixtures").FullName
$root=(New-Item -ItemType Directory (Join-Path $parent ('guest-awake-'+[guid]::NewGuid()))).FullName
$script:confirmed=$true
$script:calls=[Collections.Generic.List[string]]::new()
function Invoke-AndroidAdb {
    param([string]$Adb,[string[]]$Arguments,[int]$TimeoutMilliseconds,[switch]$AllowNonzero)
    $global:LASTEXITCODE=0
    $script:calls.Add($Arguments -join ' ')
    if($Arguments -contains 'dumpsys'){ if($script:confirmed){'mStayOnConditions=3'}else{'mStayOnConditions=1'} }
}
try {
    Set-AndroidGuestStayAwake -Adb Fixture-Adb -Serial emulator-5580 -RunDirectory $root
    if($script:calls.Count -ne 2 -or $script:calls[0] -ne '-s emulator-5580 shell svc power stayon true'){throw 'Missing explicit guest stay-awake command'}
    if(!(Test-Path "$root/power-before.txt")){throw 'Missing captured power policy'}
    $script:confirmed=$false
    $rejected=$false
    try{Set-AndroidGuestStayAwake -Adb Fixture-Adb -Serial emulator-5580 -RunDirectory $root}catch{$rejected=$true}
    if(!$rejected){throw 'Unconfirmed guest power policy was accepted'}
    Write-Output 'PASS: guest stay-awake command, captured policy and unconfirmed-policy rejection'
} finally {
    $resolved=(Resolve-Path $root).Path
    if([IO.Path]::GetDirectoryName($resolved) -ne $parent){throw 'Unexpected fixture cleanup path'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
