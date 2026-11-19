# SPDX-License-Identifier: GPL-3.0-or-later
#Requires -Version 7.0
param(
    [ValidateSet('sdk','examples','package','test')][string]$Mode = 'examples',
    [string]$AndroidSdk = $env:ANDROID_HOME,
    [string]$OutputDirectory,
    [string]$SdkImage = 'longreach-qt6-android-lollipop:llvm21',
    [string]$HostImage = 'qt6-linux-amd64-llvm21:latest',
    [switch]$SdkOnly,
    [string]$RunName = 'sdk-suite',
    [ValidateSet('on','mesa')][string]$Gpu = 'on',
    [string[]]$CaseNames,
    [ValidateSet('default','software')][string]$QtQuickBackend = 'default'
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot/../..").Path
function Invoke-Qt6AndroidTool([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program exited with code $LASTEXITCODE" }
}
if ($SdkOnly) {
    if ($PSBoundParameters.ContainsKey('Mode') -and $Mode -ne 'sdk') {
        throw '-SdkOnly cannot be combined with a mode other than sdk.'
    }
    $Mode = 'sdk'
}
if (!$OutputDirectory) { $OutputDirectory = "$repo/artifacts/qt6-android-lollipop" }
if ($Mode -in @('sdk','examples') -and
        (Get-Process -Name emulator-arm,emulator,qemu-system-armel -ErrorAction SilentlyContinue)) {
    throw 'Stop the Android emulator before compiling.'
}

switch ($Mode) {
    'sdk' {
        # Fail before downloads or provisioning when the required ready host SDK is absent.
        Invoke-Qt6AndroidTool docker @('image','inspect',$HostImage) | Out-Null
        # This is the only mode allowed to fetch build inputs or build images.
        & "$repo/scripts/fetch/qt6-android.ps1" -AndroidSdk $AndroidSdk -Scope sdk
        $tools = 'longreach-qt4-android-donut:llvm21'
        Invoke-Qt6AndroidTool docker @('build','--platform','linux/amd64','--file',
            "$repo/docker/qt4/android/Dockerfile",'--build-arg','PARALLEL_JOBS=2','--tag',$tools,$repo)
        Invoke-Qt6AndroidTool docker @('build','--platform','linux/amd64','--progress','plain',
            '--file',"$repo/docker/qt6/android/Dockerfile",'--build-arg','PARALLEL_JOBS=2',
            '--build-arg',"QT_HOST_IMAGE=$HostImage",'--target','sdk','--tag',$SdkImage,$repo)
        $output = (New-Item -ItemType Directory -Path $OutputDirectory -Force).FullName
        Invoke-Qt6AndroidTool docker @('image','inspect','--format','{{.Id}}',$SdkImage) |
            Set-Content -LiteralPath "$output/sdk-image-id.txt"
    }
    'examples' {
        try {
            $image = (Invoke-Qt6AndroidTool docker @('image','inspect','--format','{{json .}}',$SdkImage)) |
                ConvertFrom-Json
        } catch {
            throw "Cannot use SDK image '$SdkImage'. Build it explicitly with -Mode sdk or select -SdkImage. $($_.Exception.Message)"
        }
        $labels = $image.Config.Labels
        if ($image.Os -ne 'linux' -or $image.Architecture -ne 'amd64' -or
                $labels.'org.openkaryon.longreach-qt.platform' -ne 'android-lollipop-armeabi-v7a' -or
                $labels.'org.openkaryon.longreach-qt.android-api' -ne '21' -or
                $labels.'org.openkaryon.longreach-qt.version' -ne '6.8.5' -or
                $labels.'org.openkaryon.longreach-qt.compiler' -ne 'LLVM 21.1.8') {
            throw "Image '$SdkImage' is not the Qt6.8.5 / LLVM21.1.8 Android API21 ARMv7 SDK."
        }
        $output = (New-Item -ItemType Directory -Path $OutputDirectory -Force).FullName
        & python "$repo/scripts/build/android-api21/artifact-manifest.py" begin --root $output --qt-major 6 --abi armeabi-v7a --sdk-image-id $image.Id
        if ($LASTEXITCODE) { throw 'Cannot start an example generation' }
        # Pin this invocation to the inspected image even if its tag is retargeted.
        Invoke-Qt6AndroidTool docker @('run','--rm','--platform','linux/amd64','--cpus','2',
            '--memory','3g','--network','none','--mount',"type=bind,source=$repo,target=/repo,readonly",
            '--mount',"type=bind,source=$output,target=/out",$image.Id,
            'bash','/repo/scripts/build/qt6-android/build-examples.sh')
        $image.Id | Set-Content -LiteralPath "$output/examples-sdk-image-id.txt"
        & python "$repo/scripts/build/android-api21/artifact-manifest.py" finish --root $output --qt-major 6 --abi armeabi-v7a --sdk-image-id $image.Id
        if ($LASTEXITCODE) { throw 'Incomplete example generation' }
    }
    'package' {
        if (!$AndroidSdk) { throw 'Set ANDROID_HOME or pass -AndroidSdk for APK packaging.' }
        $AndroidSdk = (Resolve-Path -LiteralPath $AndroidSdk).Path
        $output = (Resolve-Path -LiteralPath $OutputDirectory).Path
        & "$PSScriptRoot/qt6-android/package-suite.ps1" -AndroidSdk $AndroidSdk -OutputDirectory $output
    }
    'test' {
        if (!$AndroidSdk) { throw 'Set ANDROID_HOME or pass -AndroidSdk for adb.' }
        $AndroidSdk = (Resolve-Path -LiteralPath $AndroidSdk).Path
        $output = (Resolve-Path -LiteralPath $OutputDirectory).Path
        & "$repo/scripts/run/qt6-android-suite.ps1" -AndroidSdk $AndroidSdk -OutputDirectory $output `
            -RunName $RunName -Gpu $Gpu -CaseNames $CaseNames -QtQuickBackend $QtQuickBackend
    }
}
