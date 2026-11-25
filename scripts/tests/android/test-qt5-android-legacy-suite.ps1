# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
<# Run the real API10 suite with recording tools; no downloads or guests. #>
param([string]$RepoRoot=(Resolve-Path "$PSScriptRoot/../../..").Path)
$ErrorActionPreference='Stop'
$parent=(New-Item -ItemType Directory -Force "$RepoRoot/build/fixtures").FullName
$fixture=Join-Path $parent ('qt5-legacy-suite-'+[guid]::NewGuid())
$global:Qt5LegacyCalls=[Collections.Generic.List[object]]::new()
$global:Qt5LegacyFailCow=$false
function Assert-Legacy([bool]$Condition,[string]$Message) { if(!$Condition){throw $Message} }
function python {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    $global:LASTEXITCODE=0
    if($Arguments[0] -like '*artifact-manifest.py'){
        $global:Qt5LegacyCalls.Add(@{kind='manifest'})
    } elseif($Arguments[0] -like '*collect-legacy-results.py'){
        $global:Qt5LegacyCalls.Add(@{kind='collect'})
    } elseif($Arguments[0] -like '*prepare-emulator.py'){
        $global:Qt5LegacyCalls.Add(@{kind='prepare'})
    } else { throw 'Unexpected Python work' }
}
function tar.exe {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    $global:LASTEXITCODE=0
    $global:Qt5LegacyCalls.Add(@{kind='extract';archive=[IO.Path]::GetFileName($Arguments[1])})
    if($Arguments[1] -like '*tools_*'){
        $tools=Join-Path $Arguments[3] 'tools'
        New-Item -ItemType Directory -Force $tools | Out-Null
        foreach($name in @('emulator-x86.exe','emulator-arm.exe')){
            [IO.File]::WriteAllText((Join-Path $tools $name),'synthetic emulator bytes')
        }
    }
}
try {
    foreach($relative in @('scripts/run/qt5-android-suite.ps1','scripts/build/android-api21/artifact-lock.ps1','tests/expected-apps.txt')){
        $destination=Join-Path $fixture $relative
        New-Item -ItemType Directory -Force (Split-Path $destination) | Out-Null
        Copy-Item -LiteralPath (Join-Path $RepoRoot $relative) -Destination $destination
    }
    New-Item -ItemType Directory -Force "$fixture/scripts/fetch","$fixture/sdk","$fixture/output","$fixture/custom emulator" | Out-Null
    $emulator="$fixture/custom emulator/emulator-x86.exe"
    [IO.File]::WriteAllText($emulator,'already-built fixture')
    $emulator=(Get-Item -LiteralPath $emulator).FullName
    [IO.File]::WriteAllText("$fixture/output/sdk-image-id.txt",'sha256:'+('a'*64))
    [IO.File]::WriteAllText("$fixture/output/apk-manifest.json",'{}')
    @'
param($Abi,$AndroidSdk,$Scope)
$global:LASTEXITCODE=0
$global:Qt5LegacyCalls.Add(@{kind='fetch'})
'@ | Set-Content "$fixture/scripts/fetch/qt5-android.ps1"
    @'
param($Abi,$AndroidSdk,$SystemDirectory,$Emulator,$Kernel,$Ramdisk,$QtQuickBackend,
      $SdkImageId,$CaseName,$Apk,$ApplicationArguments,$Package,$OutputDirectory,$BatchReceipt,$ArtifactRoot,
      [switch]$StrictCxx23,[switch]$ClassicEmulator,[switch]$NativeSensorFixture)
if (!(Test-Path -LiteralPath $ArtifactRoot)) { throw 'Missing explicit raw runner artifact root' }
$batch=Get-Content -LiteralPath $BatchReceipt -Raw | ConvertFrom-Json
$global:Qt5LegacyCalls.Add(@{kind='guest';case=$CaseName;emulator=$Emulator;
    classic=[bool]$ClassicEmulator;sensors=[bool]$NativeSensorFixture;arguments=$ApplicationArguments;batch=$batch.batch_id;
    batchSha=(Get-FileHash -LiteralPath $BatchReceipt).Hash.ToLowerInvariant();abi=$Abi})
if($CaseName -eq 'atomic-cow' -and $global:Qt5LegacyFailCow){throw 'fixture COW failure'}
'@ | Set-Content "$fixture/scripts/run/qt5-android-gingerbread.ps1"
    $entry=@{Abi='x86';AndroidSdk="$fixture/sdk";OutputDirectory="$fixture/output";RunName='fixture'}
    & "$fixture/scripts/run/qt5-android-suite.ps1" @entry -Emulator $emulator
    $guests=@($global:Qt5LegacyCalls | Where-Object { $_.kind -eq 'guest' })
    Assert-Legacy ($guests.Count -eq 14 -and $guests[0].case -eq 'atomic-cow' -and $guests[0].arguments -eq '--atomic-cow') 'Missing first COW preflight or incomplete case set'
    Assert-Legacy (@($guests | Where-Object {$_.sensors}).Count -eq 1 -and @($guests | Where-Object {$_.case -eq 'qt-selftest-extended' -and $_.sensors}).Count -eq 1) 'Missing x86 native sensor inputs'
    Assert-Legacy (@($guests | Where-Object { $_.emulator -ne $emulator -or !$_.classic }).Count -eq 0) 'Explicit classic emulator was not retained for every case'
    Assert-Legacy (@($global:Qt5LegacyCalls | Where-Object { $_.kind -eq 'extract' -and $_.archive -like 'tools_*' }).Count -eq 0) 'SDK tools overwrote the supplied emulator'
    Assert-Legacy ($global:Qt5LegacyCalls[-1].kind -eq 'collect') 'Full suite did not finalize results'
    $firstBatch=$guests[0].batch
    Assert-Legacy ($firstBatch -cmatch '^[0-9a-f]{32}$' -and @($guests | Where-Object { $_.batch -cne $firstBatch -or $_.batchSha -cne $guests[0].batchSha }).Count -eq 0) 'Cases were not bound to one batch receipt'
    $global:Qt5LegacyCalls.Clear()
    & "$fixture/scripts/run/qt5-android-suite.ps1" @entry
    $guests=@($global:Qt5LegacyCalls | Where-Object { $_.kind -eq 'guest' })
    $expected=Join-Path "$fixture/output/inputs" 'tools/emulator-x86.exe'
    Assert-Legacy ($guests.Count -eq 14 -and @($guests | Where-Object { [IO.Path]::GetFullPath($_.emulator) -ne [IO.Path]::GetFullPath($expected) -or $_.classic }).Count -eq 0) 'Default SDK emulator routing changed'
    Assert-Legacy (@($global:Qt5LegacyCalls | Where-Object { $_.kind -eq 'extract' -and $_.archive -eq 'tools_r24.4.1-windows.zip' }).Count -eq 1) 'Default SDK tools were not extracted'
    Assert-Legacy ($guests[0].batch -cne $firstBatch) 'Rerun reused a previous batch ID'
    Assert-Legacy (@(Get-ChildItem -LiteralPath "$fixture/output/fixture" -Filter 'previous-batch-*.json').Count -eq 1) 'Previous batch identity was not preserved'
    $global:Qt5LegacyCalls.Clear()
    $armEntry=@{}+$entry
    $armEntry.Abi='armeabi-v7a'
    & "$fixture/scripts/run/qt5-android-suite.ps1" @armEntry
    $guests=@($global:Qt5LegacyCalls | Where-Object { $_.kind -eq 'guest' })
    $armBatch=Get-Content -LiteralPath "$fixture/output/fixture/batch-receipt.json" -Raw | ConvertFrom-Json
    Assert-Legacy ($guests.Count -eq 13 -and $guests[0].case -eq 'strict-cxx23') 'ARM case count or order changed'
    Assert-Legacy (@($guests | Where-Object {$_.sensors}).Count -eq 1 -and @($guests | Where-Object {$_.case -eq 'qt-selftest-extended' -and $_.sensors}).Count -eq 1) 'Missing ARM native sensor inputs'
    Assert-Legacy ($armBatch.abi -ceq 'armeabi-v7a' -and $armBatch.emulator_sha256 -ceq (Get-FileHash -LiteralPath $guests[0].emulator).Hash.ToLowerInvariant()) 'ARM batch did not bind the emulator'
    Assert-Legacy (@($guests | Where-Object { $_.batch -cne $armBatch.batch_id -or $_.abi -cne 'armeabi-v7a' }).Count -eq 0) 'ARM cases mixed batch identities'
    foreach($name in @('final-results.json','final-results-table.md','apk-native-abi-check.json')){
        [IO.File]::WriteAllText("$fixture/output/$name",'old success')
    }
    $global:Qt5LegacyCalls.Clear()
    $global:Qt5LegacyFailCow=$true
    $failed=$false
    try { & "$fixture/scripts/run/qt5-android-suite.ps1" @entry -Emulator $emulator }
    catch { if($_.Exception.Message -ne 'fixture COW failure'){throw};$failed=$true }
    Assert-Legacy $failed 'COW failure did not stop the suite'
    Assert-Legacy (@($global:Qt5LegacyCalls | Where-Object { $_.kind -eq 'guest' }).Count -eq 1 -and $global:Qt5LegacyCalls[-1].kind -ne 'collect') 'Cases continued after failed preflight'
    foreach($name in @('final-results.json','final-results-table.md','apk-native-abi-check.json')){
        Assert-Legacy (!(Test-Path -LiteralPath "$fixture/output/$name")) 'Failed run retained old aggregate success'
    }
    Write-Output 'PASS: explicit/default emulator routing, x86/ARM batch rotation and binding, first COW gate and stale-result invalidation'
} finally {
    if(Test-Path -LiteralPath $fixture){
        $resolved=(Resolve-Path -LiteralPath $fixture).Path
        if([IO.Path]::GetDirectoryName($resolved) -ne $parent){throw 'Unexpected fixture cleanup path'}
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
    Remove-Variable -Name Qt5LegacyCalls,Qt5LegacyFailCow -Scope Global -ErrorAction SilentlyContinue
}
