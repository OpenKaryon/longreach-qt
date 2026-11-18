# SPDX-License-Identifier: GPL-3.0-or-later
#Requires -Version 7.0
param(
    [string]$AndroidSdk = $env:ANDROID_HOME,
    [string]$OutputDirectory,
    [switch]$SdkOnly,
    [string]$HostImage = 'qt6-linux-amd64-llvm21:latest'
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot/../..").Path
function Invoke-Qt6AndroidTool([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program exited with code $LASTEXITCODE" }
}
if (!$AndroidSdk) { throw 'Set ANDROID_HOME or pass -AndroidSdk with platform35 and Build Tools36.0.0.' }
$AndroidSdk = (Resolve-Path -LiteralPath $AndroidSdk).Path
if (!$OutputDirectory) { $OutputDirectory = "$repo/artifacts/qt6-android-lollipop" }
$output = (New-Item -ItemType Directory -Path $OutputDirectory -Force).FullName
if (Get-Process -Name emulator-arm,emulator,qemu-system-armel -ErrorAction SilentlyContinue) {
    throw 'Stop the Android emulator before building the SDK.'
}
Invoke-Qt6AndroidTool docker @('image','inspect',$HostImage) | Out-Null
& "$repo/scripts/fetch/qt6-android.ps1" -AndroidSdk $AndroidSdk
$tools = 'longreach-qt4-android-donut:llvm21'
Invoke-Qt6AndroidTool docker @('build','--platform','linux/amd64','--file',
    "$repo/docker/qt4/android/Dockerfile",'--build-arg','PARALLEL_JOBS=2','--tag',$tools,$repo)
$image = 'longreach-qt6-android-lollipop:llvm21'
Invoke-Qt6AndroidTool docker @('build','--platform','linux/amd64','--progress','plain',
    '--file',"$repo/docker/qt6/android/Dockerfile",'--build-arg','PARALLEL_JOBS=2',
    '--build-arg',"QT_HOST_IMAGE=$HostImage",'--target','sdk','--tag',$image,$repo)
$sdkImageId=((Invoke-Qt6AndroidTool docker @('image','inspect','--format','{{.Id}}',$image)) -join '').Trim()
$sdkImageId | Set-Content -LiteralPath "$output/sdk-image-id.txt"
if ($SdkOnly) { return }
& python "$repo/scripts/build/android-api21/artifact-manifest.py" begin --root $output --qt-major 6 --abi armeabi-v7a --sdk-image-id $sdkImageId
if ($LASTEXITCODE) { throw 'Cannot start an example generation' }
Invoke-Qt6AndroidTool docker @('run','--rm','--platform','linux/amd64','--cpus','2',
    '--memory','3g','--network','none','--mount',"type=bind,source=$repo,target=/repo,readonly",
    '--mount',"type=bind,source=$output,target=/out",$sdkImageId,
    'bash','/repo/scripts/build/qt6-android/build-examples.sh')
& python "$repo/scripts/build/android-api21/artifact-manifest.py" finish --root $output --qt-major 6 --abi armeabi-v7a --sdk-image-id $sdkImageId
if ($LASTEXITCODE) { throw 'Incomplete example generation' }
& "$PSScriptRoot/qt6-android/package-suite.ps1" -AndroidSdk $AndroidSdk -OutputDirectory $output
