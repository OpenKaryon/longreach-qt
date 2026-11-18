# SPDX-License-Identifier: GPL-3.0-or-later

param(
    [string] $AndroidSdk = $env:ANDROID_HOME,
    [string] $OutputDirectory
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot/../..").Path
function Invoke-AndroidSuiteTool([string] $Program, [string[]] $Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program exited with code $LASTEXITCODE." }
}
if (!$AndroidSdk) { throw 'Set ANDROID_HOME or pass -AndroidSdk.' }
$AndroidSdk = (Resolve-Path -LiteralPath $AndroidSdk).Path
if (!$OutputDirectory) { $OutputDirectory = Join-Path $repo 'artifacts/qt5-android-gingerbread' }
$output = (Resolve-Path -LiteralPath $OutputDirectory).Path
& python "$repo/scripts/build/android-api21/artifact-manifest.py" check-apks --root $output --qt-major 5 --abi armeabi-v7a
if ($LASTEXITCODE) { throw 'Refusing incomplete or mismatched APK generation' }
$inputs = Join-Path $repo 'downloads/android-gingerbread'
$media = (New-Item -ItemType Directory -Force -Path "$output/inputs").FullName
& "$repo/scripts/fetch/qt5-android.ps1" -AndroidSdk $AndroidSdk
Invoke-AndroidSuiteTool tar.exe @('-xf', "$inputs/android-2.3.3_r02-linux.zip", '-C', $media)
Invoke-AndroidSuiteTool tar.exe @('-xf', "$inputs/tools_r24.4.1-windows.zip", '-C', $media)
Invoke-AndroidSuiteTool python @("$repo/scripts/build/qt5-android/prepare-emulator.py",
    "$inputs/android-2.3.3_r02-linux.zip", "$media/ramdisk-api10-armv7.img")
$guest = @{
    AndroidSdk = $AndroidSdk
    SystemDirectory = "$media/android-2.3.3_r02-linux/images"
    Emulator = "$media/tools/emulator-arm.exe"
    Kernel = "$inputs/kernel-qemu-armv7"
    Ramdisk = "$media/ramdisk-api10-armv7.img"
    QtQuickBackend = 'software'
}
$runner = "$PSScriptRoot/qt5-android-gingerbread.ps1"
& $runner @guest -Apk "$output/apk/qt-selftest.apk" -StrictCxx23 `
    -Package org.longreachqt.examples.qtselftest -OutputDirectory "$output/run/strict-cxx23"
$apps = @(Get-Content -LiteralPath "$repo/tests/expected-apps.txt" |
    ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^[a-z]' -and $_ -ne 'smoke-runner' })
foreach ($app in $apps) {
    & $runner @guest -Apk "$output/apk/$app.apk" -ApplicationArguments '--selftest' `
        -Package ("org.longreachqt.examples." + $app.Replace('-', '')) -OutputDirectory "$output/run/$app"
}

& $runner @guest -Apk "$output/apk/extended/qt-selftest.apk" -StrictCxx23 `
    -Package org.longreachqt.examples.qtselftest -OutputDirectory "$output/run/strict-cxx23-extended"
& $runner @guest -Apk "$output/apk/extended/qt-selftest.apk" -ApplicationArguments '--selftest' `
    -Package org.longreachqt.examples.qtselftest -OutputDirectory "$output/run/qt-selftest-extended"

foreach ($app in @('widgets-gallery', 'quick-qml-gallery')) {
    & $runner @guest -Apk "$output/apk/$app.apk" -ApplicationArguments '--gallery-selftest' `
        -Package ("org.longreachqt.examples." + $app.Replace('-', '')) -OutputDirectory "$output/run/$app-render"
}
