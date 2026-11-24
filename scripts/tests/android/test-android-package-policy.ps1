# SPDX-License-Identifier: GPL-3.0-or-later
param([string]$RepoRoot=(Resolve-Path "$PSScriptRoot/../../..").Path)
$ErrorActionPreference='Stop'
. "$RepoRoot/scripts/build/qt5-android/package-example-policy.ps1"
$parent=(New-Item -ItemType Directory -Force "$RepoRoot/build/fixtures").FullName
$root=(New-Item -ItemType Directory (Join-Path $parent ('imageformats-'+[guid]::NewGuid()))).FullName
try {
    foreach($name in @('libplugins_imageformats_qgif_x86.so','libplugins_imageformats_qjpeg_x86.so',
                      'libplugins_imageformats_qsvg_x86.so','libplugins_imageformats_qico_x86.so',
                      'libplugins_imageformats_qico_arm64-v8a.so','libQt5Gui_x86.so')) {
        [IO.File]::WriteAllText((Join-Path $root $name),'fixture')
    }
    Select-AndroidImageFormats $root x86 @()
    if(@(Get-ChildItem $root).Count -ne 6){throw 'Default selection removed a plugin'}
    Select-AndroidImageFormats $root x86 @('gif','jpeg','svg')
    if(@(Get-ChildItem $root).Count -ne 5 -or (Test-Path "$root/libplugins_imageformats_qico_x86.so")){throw 'Incorrect image-plugin selection'}
    if(!(Test-Path "$root/libQt5Gui_x86.so") -or !(Test-Path "$root/libplugins_imageformats_qsvg_x86.so")){throw 'Required library removed'}
    $metadata=Get-AndroidExampleMetadata qt-selftest
    if($metadata -notmatch 'android.app.background_running' -or $metadata -notmatch 'android:value="true"'){throw 'Headless selftest has no background event loop policy'}
    if(Get-AndroidExampleMetadata quick-qml-gallery){throw 'GUI example lifecycle was changed'}
    Write-Output 'PASS: image-plugin selection, headless selftest event loop and unchanged GUI lifecycle'
} finally {
    $resolved=(Resolve-Path $root).Path
    if([IO.Path]::GetDirectoryName($resolved) -ne $parent){throw 'Unexpected fixture cleanup path'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
