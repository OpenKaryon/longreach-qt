# SPDX-License-Identifier: GPL-3.0-or-later

param(
    [ValidateSet('armeabi-v7a','arm64-v8a','x86','x86_64')][string]$Abi = 'armeabi-v7a',
    [string]$RunName = 'run',
    [ValidateSet('on','mesa')][string]$Gpu = 'on',
    [string[]]$CaseNames,
    [switch]$DebugQtPlugins,
    [ValidateSet('default','software')][string]$QtQuickBackend = 'default',
    [string] $AndroidSdk = $env:ANDROID_HOME,
    [string] $OutputDirectory,
    [string] $Emulator
)

$ErrorActionPreference = 'Stop'
if ($Emulator -and $Abi -ne 'x86') { throw '-Emulator is only supported for the API10 x86 suite' }
if ($Emulator) { $Emulator=(Get-Item -LiteralPath $Emulator).FullName }
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
. "$repo/scripts/build/android-api21/artifact-lock.ps1"
$artifactLock=Enter-AndroidArtifactLock $output
try {
# A failed new run must not leave an earlier batch advertised as complete.
Clear-AndroidResultAggregates $output
& python "$repo/scripts/build/android-api21/artifact-manifest.py" check-apks --root $output --qt-major 5 --abi $Abi --artifact-lease-held
if ($LASTEXITCODE) { throw 'Refusing incomplete or mismatched APK generation' }
$inputs = Join-Path $repo 'downloads/android-gingerbread'
$media = (New-Item -ItemType Directory -Force -Path "$output/inputs").FullName
& "$repo/scripts/fetch/qt5-android.ps1" -Abi $Abi -AndroidSdk $AndroidSdk -Scope test
if ($Abi -eq 'x86') {
    Invoke-AndroidSuiteTool tar.exe @('-xf', "$inputs/x86-10_r05.zip", '-C', $media)
    if (!$Emulator) { Invoke-AndroidSuiteTool tar.exe @('-xf', "$inputs/tools_r24.4.1-windows.zip", '-C', $media) }
    $guest = @{
        Abi = $Abi
        AndroidSdk = $AndroidSdk
        SystemDirectory = "$media/x86"
        Emulator = $(if ($Emulator) { $Emulator } else { "$media/tools/emulator-x86.exe" })
        ClassicEmulator = [bool]$Emulator
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
$guest.SdkImageId=(Get-Content -LiteralPath "$output/sdk-image-id.txt" -Raw).Trim()
$runRoot=(New-Item -ItemType Directory -Force -Path "$output/$RunName").FullName
$batchPath=Join-Path $runRoot 'batch-receipt.json'
if (Test-Path -LiteralPath $batchPath) {
    $item=Get-Item -LiteralPath $batchPath
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid existing API10 batch receipt' }
    Copy-Item -LiteralPath $batchPath -Destination (Join-Path $runRoot ('previous-batch-'+[guid]::NewGuid().ToString('N')+'.json'))
}
$batch=@{schema_version=1;batch_id=[guid]::NewGuid().ToString('N');run=$RunName;abi=$Abi;api=10;
    sdk_image_id=$guest.SdkImageId;apk_manifest_sha256=(Get-FileHash "$output/apk-manifest.json").Hash.ToLowerInvariant();
    emulator_sha256=(Get-FileHash -LiteralPath $guest.Emulator).Hash.ToLowerInvariant();started_utc=[DateTime]::UtcNow.ToString('o')}
$temporary=$batchPath+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
try {
    $batch | ConvertTo-Json | Set-Content -LiteralPath $temporary -Encoding utf8
    # The artifact lease prevents another reader/runner from entering this root.
    [IO.File]::Move($temporary,$batchPath,$true)
} finally { [IO.File]::Delete($temporary) }
$guest.BatchReceipt=$batchPath
$guest.ArtifactRoot=$output
$runner = "$PSScriptRoot/qt5-android-gingerbread.ps1"
if ($Abi -eq 'x86') {
    & $runner @guest -CaseName atomic-cow -Apk "$output/apk/qt-selftest.apk" `
        -ApplicationArguments '--atomic-cow' -Package org.longreachqt.examples.qtselftest `
        -OutputDirectory "$output/$RunName/atomic-cow"
}
& $runner @guest -CaseName strict-cxx23 -Apk "$output/apk/qt-selftest.apk" -StrictCxx23 `
    -Package org.longreachqt.examples.qtselftest -OutputDirectory "$output/$RunName/strict-cxx23"
$apps = @(Get-Content -LiteralPath "$repo/tests/expected-apps.txt" |
    ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^[a-z]' -and $_ -ne 'smoke-runner' })
foreach ($app in $apps) {
    & $runner @guest -CaseName $app -Apk "$output/apk/$app.apk" -ApplicationArguments '--selftest' `
        -Package ("org.longreachqt.examples." + $app.Replace('-', '')) -OutputDirectory "$output/$RunName/$app"
}

& $runner @guest -CaseName strict-cxx23-extended -Apk "$output/apk/extended/qt-selftest.apk" -StrictCxx23 `
    -Package org.longreachqt.examples.qtselftest -OutputDirectory "$output/$RunName/strict-cxx23-extended"
$sensorOptions=@{}
if ($Abi -eq 'x86') { $sensorOptions.NativeSensorFixture=$true }
& $runner @guest @sensorOptions -CaseName qt-selftest-extended -Apk "$output/apk/extended/qt-selftest.apk" -ApplicationArguments '--selftest' `
    -Package org.longreachqt.examples.qtselftest -OutputDirectory "$output/$RunName/qt-selftest-extended"

foreach ($app in @('widgets-gallery', 'quick-qml-gallery')) {
    & $runner @guest -CaseName "$app-render" -Apk "$output/apk/$app.apk" -ApplicationArguments '--gallery-selftest' `
        -Package ("org.longreachqt.examples." + $app.Replace('-', '')) -OutputDirectory "$output/$RunName/$app-render"
}

Invoke-AndroidSuiteTool python @("$repo/scripts/build/qt5-android/collect-legacy-results.py", '--artifact-lease-held', '--root', $output, '--run', $RunName, '--abi', $Abi)

} finally { if ($artifactLock) { $artifactLock.Dispose() } }
