# SPDX-License-Identifier: GPL-3.0-or-later
#Requires -Version 7.0

param(
    [string] $AndroidSdk = $env:ANDROID_HOME,
    [string] $OutputDirectory,
    [switch] $SdkOnly
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot/../..").Path
function Invoke-AndroidBuildTool([string] $Program, [string[]] $Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program exited with code $LASTEXITCODE." }
}
if (!$AndroidSdk) { throw 'Set ANDROID_HOME or pass -AndroidSdk with platform 35 and Build Tools 36.0.0.' }
$AndroidSdk = (Resolve-Path -LiteralPath $AndroidSdk).Path
if (!$OutputDirectory) { $OutputDirectory = Join-Path $repo 'artifacts/qt5-android-gingerbread' }
$output = (New-Item -ItemType Directory -Path $OutputDirectory -Force).FullName
if (Get-Process -Name emulator-arm, emulator, qemu-system-armel -ErrorAction SilentlyContinue) {
    throw 'Stop the Android emulator before starting the SDK build.'
}
& "$repo/scripts/fetch/qt5-android.ps1" -AndroidSdk $AndroidSdk
$toolsImage = 'longreach-qt4-android-donut:llvm21'
Invoke-AndroidBuildTool docker @('build','--platform','linux/amd64','--file',
    "$repo/docker/qt4/android/Dockerfile",'--build-arg','PARALLEL_JOBS=2','--tag',$toolsImage,$repo)
$image = 'longreach-qt5-android-gingerbread:llvm21'
Invoke-AndroidBuildTool docker @('build', '--platform', 'linux/amd64', '--progress', 'plain',
    '--file', "$repo/docker/qt5/android/Dockerfile", '--build-arg', 'PARALLEL_JOBS=2',
    '--target', 'sdk', '--tag', $image, $repo)

$sdkImageId=((Invoke-AndroidBuildTool docker @('image','inspect','--format','{{.Id}}',$image)) -join '').Trim()
if (!$SdkOnly) {
    & python "$repo/scripts/build/android-api21/artifact-manifest.py" begin --root $output --qt-major 5 --abi armeabi-v7a --sdk-image-id $sdkImageId
    if ($LASTEXITCODE) { throw 'Cannot start an example generation' }
}

$sdk = Join-Path $output 'sdk'
if (Test-Path -LiteralPath $sdk) {
    $item = Get-Item -LiteralPath $sdk
    $parent = [IO.Path]::GetDirectoryName($item.FullName)
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
            ![string]::Equals($parent, $output, [StringComparison]::OrdinalIgnoreCase) -or
            !(Test-Path -LiteralPath "$sdk/.longreach-sdk-export")) {
        throw "Refusing to replace an unowned SDK export: $sdk"
    }
    Remove-Item -LiteralPath $item.FullName -Recurse -Force
}
New-Item -ItemType Directory -Path $sdk | Out-Null
[IO.File]::WriteAllText("$sdk/.longreach-sdk-export", "$sdkImageId`n")
$native = (New-Item -ItemType Directory -Path "$output/native" -Force).FullName
$container = ((Invoke-AndroidBuildTool docker @('create', $sdkImageId)) -join '').Trim()
if ($container -notmatch '^[0-9a-f]{64}$') { throw "Unexpected export container ID: $container" }
try {
    Invoke-AndroidBuildTool docker @('cp', "${container}:/opt/qt5-android-armeabi-v7a-llvm/.", $sdk)
    Invoke-AndroidBuildTool docker @('cp', "${container}:/opt/longreach-android/lib/libc++_shared.so",
        "$native/libc++_shared.so")
} finally {
    Invoke-AndroidBuildTool docker @('rm', $container) | Out-Null
}
$sdkImageId | Set-Content -LiteralPath "$output/sdk-image-id.txt"
if ($SdkOnly) { return }

Invoke-AndroidBuildTool docker @('run', '--rm', '--platform', 'linux/amd64', '--cpus', '2',
    '--memory', '3g', '--network', 'none',
    '--mount', "type=bind,source=$repo,target=/repo,readonly",
    '--mount', "type=bind,source=$output,target=/out",
    '--mount', "type=bind,source=$AndroidSdk,target=/android-sdk,readonly",
    '--env', 'ANDROID_SDK_ROOT=/android-sdk', $sdkImageId,
    'bash', '/repo/scripts/build/qt5-android/build-examples.sh')
& python "$repo/scripts/build/android-api21/artifact-manifest.py" finish --root $output --qt-major 5 --abi armeabi-v7a --sdk-image-id $sdkImageId
if ($LASTEXITCODE) { throw 'Incomplete example generation' }

$apps = @(Get-Content -LiteralPath "$repo/tests/expected-apps.txt" |
    ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^[a-z]' -and $_ -ne 'smoke-runner' })
foreach ($app in $apps) {
    $deployment = Join-Path $output "deployment/$app"
    & "$PSScriptRoot/qt5-android/package.ps1" -QtSdk $sdk -AndroidSdk $AndroidSdk `
        -NativeLibrary "$deployment/libs/armeabi-v7a/lib${app}_armeabi-v7a.so" `
        -RuntimeLibrary "$native/libc++_shared.so" -DeploymentDirectory $deployment `
        -OutputDirectory "$output/apk" -Package ("org.longreachqt.examples." + $app.Replace('-', ''))
}

$extended = Join-Path $output 'deployment-extended/qt-selftest'
& "$PSScriptRoot/qt5-android/package.ps1" -QtSdk $sdk -AndroidSdk $AndroidSdk `
    -NativeLibrary "$extended/libs/armeabi-v7a/libqt-selftest_armeabi-v7a.so" `
    -RuntimeLibrary "$native/libc++_shared.so" -DeploymentDirectory $extended `
    -OutputDirectory "$output/apk/extended" -Package org.longreachqt.examples.qtselftest

& python "$repo/scripts/build/android-api21/artifact-manifest.py" record-apks --root $output --qt-major 5 --abi armeabi-v7a
if ($LASTEXITCODE) { throw 'Cannot bind APKs to the completed example generation' }
