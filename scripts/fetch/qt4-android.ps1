# SPDX-License-Identifier: GPL-3.0-or-later
param([ValidateSet('x86','x86_64','arm64-v8a')][string]$Abi='x86_64',
      [ValidateSet('all','sdk','test')][string]$Scope='all', [string]$AndroidSdk=$env:ANDROID_HOME)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path "$PSScriptRoot/../..").Path
if ($Abi -eq 'x86') {
    & "$PSScriptRoot/qt5-android.ps1" -Abi $Abi -Scope $Scope -PlatformOnly -AndroidSdk $AndroidSdk
} else {
    & "$PSScriptRoot/qt6-android.ps1" -Abi $Abi -Scope $Scope -PlatformOnly -AndroidSdk $AndroidSdk
}
if ($Scope -eq 'test') { return }
$lock=Get-Content "$PSScriptRoot/locks/qt4-android-api21-inputs.json" -Raw | ConvertFrom-Json
foreach ($source in $lock.shared_sources) {
    & python "$PSScriptRoot/fetch.py" $source.url "$repo/downloads/$($source.file)" $source.sha256
    if ($LASTEXITCODE) { throw "Cannot fetch $($source.file)" }
}
