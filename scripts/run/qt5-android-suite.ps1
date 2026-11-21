# SPDX-License-Identifier: GPL-3.0-or-later

param(
    [ValidateSet('armeabi-v7a','arm64-v8a','x86','x86_64')][string]$Abi = 'armeabi-v7a',
    [string]$RunName = 'run',
    [ValidateSet('on','mesa')][string]$Gpu = 'on',
    [string[]]$CaseNames,
    [switch]$DebugQtPlugins,
    [ValidateSet('default','software')][string]$QtQuickBackend = 'default',
    [string] $AndroidSdk = $env:ANDROID_HOME,
    [string] $OutputDirectory
)

$ErrorActionPreference = 'Stop'
if ($Abi -notin @('armeabi-v7a','x86')) {
    $options=@{} + $PSBoundParameters
    $options.RunName=$RunName
    & "$PSScriptRoot/android-api21-suite.ps1" -QtMajor 5 @options
    return
}
if ($CaseNames -or $DebugQtPlugins) { throw 'Partial selection and plugin diagnostics require the API21 suite' }
if ($RunName -notmatch '^[a-z0-9-]+$') { throw 'Invalid run name' }

$repo = (Resolve-Path "$PSScriptRoot/../..").Path
function Invoke-AndroidSuiteTool([string] $Program, [string[]] $Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program exited with code $LASTEXITCODE." }
}
if (!$AndroidSdk) { throw 'Set ANDROID_HOME or pass -AndroidSdk.' }
$AndroidSdk = (Resolve-Path -LiteralPath $AndroidSdk).Path
if (!$OutputDirectory) {
    $suffix=if ($Abi -eq 'x86') { '-x86' } else { '' }
    $OutputDirectory = Join-Path $repo "artifacts/qt5-android-gingerbread$suffix"
}
$output = (Resolve-Path -LiteralPath $OutputDirectory).Path
& python "$repo/scripts/build/android-api21/artifact-manifest.py" check-apks --root $output --qt-major 5 --abi $Abi
if ($LASTEXITCODE) { throw 'Refusing incomplete or mismatched APK generation' }
$inputs = Join-Path $repo 'downloads/android-gingerbread'
$media = (New-Item -ItemType Directory -Force -Path "$output/inputs").FullName
& "$repo/scripts/fetch/qt5-android.ps1" -Abi $Abi -AndroidSdk $AndroidSdk -Scope test
if ($Abi -eq 'x86') {
    Invoke-AndroidSuiteTool tar.exe @('-xf', "$inputs/x86-10_r05.zip", '-C', $media)
    Invoke-AndroidSuiteTool tar.exe @('-xf', "$inputs/tools_r24.4.1-windows.zip", '-C', $media)
    $guest = @{
        Abi = $Abi
        AndroidSdk = $AndroidSdk
        SystemDirectory = "$media/x86"
        Emulator = "$media/tools/emulator-x86.exe"
        Kernel = "$media/x86/kernel-qemu"
        Ramdisk = "$media/x86/ramdisk.img"
        QtQuickBackend = 'software'
    }
} else {
    Invoke-AndroidSuiteTool tar.exe @('-xf', "$inputs/android-2.3.3_r02-linux.zip", '-C', $media)
    Invoke-AndroidSuiteTool tar.exe @('-xf', "$inputs/tools_r24.4.1-windows.zip", '-C', $media)
    Invoke-AndroidSuiteTool python @("$repo/scripts/build/qt5-android/prepare-emulator.py",
        "$inputs/android-2.3.3_r02-linux.zip", "$media/ramdisk-api10-armv7.img")
    $guest = @{
        Abi = $Abi
        AndroidSdk = $AndroidSdk
        SystemDirectory = "$media/android-2.3.3_r02-linux/images"
        Emulator = "$media/tools/emulator-arm.exe"
        Kernel = "$inputs/kernel-qemu-armv7"
        Ramdisk = "$media/ramdisk-api10-armv7.img"
        QtQuickBackend = 'software'
    }
}
$runner = "$PSScriptRoot/qt5-android-gingerbread.ps1"
& $runner @guest -Apk "$output/apk/qt-selftest.apk" -StrictCxx23 `
    -Package org.longreachqt.examples.qtselftest -OutputDirectory "$output/$RunName/strict-cxx23"
$apps = @(Get-Content -LiteralPath "$repo/tests/expected-apps.txt" |
    ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^[a-z]' -and $_ -ne 'smoke-runner' })
foreach ($app in $apps) {
    & $runner @guest -Apk "$output/apk/$app.apk" -ApplicationArguments '--selftest' `
        -Package ("org.longreachqt.examples." + $app.Replace('-', '')) -OutputDirectory "$output/$RunName/$app"
}

& $runner @guest -Apk "$output/apk/extended/qt-selftest.apk" -StrictCxx23 `
    -Package org.longreachqt.examples.qtselftest -OutputDirectory "$output/$RunName/strict-cxx23-extended"
& $runner @guest -Apk "$output/apk/extended/qt-selftest.apk" -ApplicationArguments '--selftest' `
    -Package org.longreachqt.examples.qtselftest -OutputDirectory "$output/$RunName/qt-selftest-extended"

foreach ($app in @('widgets-gallery', 'quick-qml-gallery')) {
    & $runner @guest -Apk "$output/apk/$app.apk" -ApplicationArguments '--gallery-selftest' `
        -Package ("org.longreachqt.examples." + $app.Replace('-', '')) -OutputDirectory "$output/$RunName/$app-render"
}
