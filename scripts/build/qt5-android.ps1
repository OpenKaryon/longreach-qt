# SPDX-License-Identifier: GPL-3.0-or-later
#Requires -Version 7.0
param(
    [ValidateSet('sdk','examples','package','test')][string]$Mode='examples',
    [ValidateSet('armeabi-v7a','arm64-v8a','x86_64')][string]$Abi='armeabi-v7a',
    [string]$AndroidSdk=$env:ANDROID_HOME,
    [string]$OutputDirectory,
    [string]$SdkImage,
    [switch]$SdkOnly,
    [string]$RunName='sdk-suite',
    [ValidateSet('on','mesa')][string]$Gpu='on',
    [string[]]$CaseNames,
    [switch]$DebugQtPlugins,
    [ValidateSet('default','software')][string]$QtQuickBackend='default'
)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path "$PSScriptRoot/../..").Path
function Invoke-AndroidBuildTool([string]$Program,[string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program exited with code $LASTEXITCODE." }
}
if ($SdkOnly) {
    if ($PSBoundParameters.ContainsKey('Mode') -and $Mode -ne 'sdk') { throw '-SdkOnly cannot be combined with a mode other than sdk.' }
    $Mode='sdk'
}
$api=if ($Abi -eq 'armeabi-v7a') { '10' } else { '21' }
$platform=if ($api -eq '10') { "android-gingerbread-$Abi" } else { "android-lollipop-$Abi" }
$profile=if ($api -eq '10') { 'gingerbread' } else { "lollipop-$Abi" }
if (!$SdkImage) { $SdkImage="longreach-qt5-android-${profile}:llvm21" }
if (!$OutputDirectory) { $OutputDirectory="$repo/artifacts/qt5-android-$profile" }
if ($Mode -in @('sdk','examples') -and
        (Get-Process -Name emulator-arm,emulator,emulator-ranchu-arm64,emulator64-ranchu-arm64,qemu-system-armel,qemu-system-aarch64,emulator-x86,emulator64-x86,qemu-system-x86_64,qemu-system-x86_64-headless -ErrorAction SilentlyContinue)) {
    throw 'Stop the Android emulator before compiling.'
}
if (!$AndroidSdk) { throw 'Set ANDROID_HOME or pass -AndroidSdk.' }
$AndroidSdk=(Resolve-Path -LiteralPath $AndroidSdk).Path
switch ($Mode) {
    'sdk' {
        & "$repo/scripts/fetch/qt5-android.ps1" -Abi $Abi -Scope sdk -AndroidSdk $AndroidSdk
        $tools='longreach-qt4-android-donut:llvm21'
        Invoke-AndroidBuildTool docker @('build','--platform','linux/amd64','--file',
            "$repo/docker/qt4/android/Dockerfile",'--build-arg','PARALLEL_JOBS=2','--tag',$tools,$repo)
        Invoke-AndroidBuildTool docker @('build','--platform','linux/amd64','--progress','plain',
            '--file',"$repo/docker/qt5/android/Dockerfile",'--build-arg','PARALLEL_JOBS=2',
            '--build-arg',"ANDROID_ABI=$Abi",'--target','sdk','--tag',$SdkImage,$repo)
        $output=(New-Item -ItemType Directory -Path $OutputDirectory -Force).FullName
        Invoke-AndroidBuildTool docker @('image','inspect','--format','{{.Id}}',$SdkImage) | Set-Content "$output/sdk-image-id.txt"
    }
    'examples' {
        try {
            $image=(Invoke-AndroidBuildTool docker @('image','inspect','--format','{{json .}}',$SdkImage)) | ConvertFrom-Json
        } catch { throw "Cannot use SDK image '$SdkImage'. Build it explicitly with -Mode sdk or select -SdkImage. $($_.Exception.Message)" }
        $labels=$image.Config.Labels
        if ($image.Os -ne 'linux' -or $image.Architecture -ne 'amd64' -or
                $labels.'org.openkaryon.longreach-qt.platform' -ne $platform -or
                $labels.'org.openkaryon.longreach-qt.android-api' -ne $api -or
                $labels.'org.openkaryon.longreach-qt.version' -ne '5.15.19' -or
                $labels.'org.openkaryon.longreach-qt.compiler' -ne 'LLVM 21.1.8') {
            throw "Image '$SdkImage' is not the Qt5.15.19 / LLVM21.1.8 API$api $Abi SDK."
        }
        $output=(New-Item -ItemType Directory -Path $OutputDirectory -Force).FullName
        & python "$repo/scripts/build/android-api21/artifact-manifest.py" begin --root $output --qt-major 5 --abi $Abi --sdk-image-id $image.Id
        if ($LASTEXITCODE) { throw 'Cannot start an example generation' }
        $sdk=Join-Path $output 'sdk'
        if (Test-Path -LiteralPath $sdk) {
            $item=Get-Item -LiteralPath $sdk
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
                    ![string]::Equals([IO.Path]::GetDirectoryName($item.FullName),$output,[StringComparison]::OrdinalIgnoreCase) -or
                    !(Test-Path -LiteralPath "$sdk/.longreach-sdk-export")) { throw "Refusing to replace an unowned SDK export: $sdk" }
            Remove-Item -LiteralPath $item.FullName -Recurse -Force
        }
        New-Item -ItemType Directory -Path $sdk | Out-Null
        [IO.File]::WriteAllText("$sdk/.longreach-sdk-export","$($image.Id)`n")
        $native=(New-Item -ItemType Directory -Path "$output/native" -Force).FullName
        $container=((Invoke-AndroidBuildTool docker @('create',$image.Id)) -join '').Trim()
        if ($container -notmatch '^[0-9a-f]{64}$') { throw "Unexpected export container ID: $container" }
        try {
            Invoke-AndroidBuildTool docker @('cp',"${container}:/opt/qt5-android-$Abi-llvm/.",$sdk)
            Invoke-AndroidBuildTool docker @('cp',"${container}:/opt/longreach-android/lib/libc++_shared.so","$native/libc++_shared.so")
            & docker cp "${container}:/opt/longreach-reports/." $output 2>$null
            if ($LASTEXITCODE -ne 0 -and $api -eq '21') { throw 'Missing API21 SDK producer reports' }
        } finally { Invoke-AndroidBuildTool docker @('rm',$container) | Out-Null }
        $image.Id | Set-Content "$output/sdk-image-id.txt"
        Invoke-AndroidBuildTool docker @('run','--rm','--platform','linux/amd64','--cpus','2','--memory','3g','--network','none',
            '--mount',"type=bind,source=$repo,target=/repo,readonly",'--mount',"type=bind,source=$output,target=/out",
            '--mount',"type=bind,source=$AndroidSdk,target=/android-sdk,readonly",'--env','ANDROID_SDK_ROOT=/android-sdk',
            $image.Id,'bash','/repo/scripts/build/qt5-android/build-examples.sh')
        $image.Id | Set-Content "$output/examples-sdk-image-id.txt"
        & python "$repo/scripts/build/android-api21/artifact-manifest.py" finish --root $output --qt-major 5 --abi $Abi --sdk-image-id $image.Id
        if ($LASTEXITCODE) { throw 'Incomplete example generation' }
    }
    'package' {
        $output=(Resolve-Path -LiteralPath $OutputDirectory).Path
        & "$PSScriptRoot/qt5-android/package-suite.ps1" -Abi $Abi -AndroidSdk $AndroidSdk -OutputDirectory $output
    }
    'test' {
        $output=(Resolve-Path -LiteralPath $OutputDirectory).Path
        & "$repo/scripts/run/qt5-android-suite.ps1" -Abi $Abi -AndroidSdk $AndroidSdk -OutputDirectory $output `
            -RunName $RunName -Gpu $Gpu -CaseNames $CaseNames -DebugQtPlugins:$DebugQtPlugins -QtQuickBackend $QtQuickBackend
    }
}
