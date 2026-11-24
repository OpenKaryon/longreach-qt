# SPDX-License-Identifier: GPL-3.0-or-later
#Requires -Version 7.0
param(
    [ValidateSet('sdk','examples','package','test')][string]$Mode = 'examples',
    [ValidateSet('armeabi-v7a','arm64-v8a','x86','x86_64')][string]$Abi = 'armeabi-v7a',
    [string]$AndroidSdk = $env:ANDROID_HOME,
    [string]$OutputDirectory,
    [string]$SdkImage,
    [string]$HostImage = 'qt6-linux-amd64-llvm21:latest',
    [switch]$SdkOnly,
    [string]$RunName = 'sdk-suite',
    [ValidateSet('on','mesa')][string]$Gpu = 'on',
    [string[]]$CaseNames,
    [switch]$DebugQtPlugins,
    [ValidateSet('default','software')][string]$QtQuickBackend = 'default',
    [ValidateRange(1,256)][int]$ParallelJobs=2,
    [switch]$NoCache,
    [string]$DockerBuildFlagsJson='[]'
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot/../..").Path
. "$repo/scripts/run/android/android-emulator-state.ps1"
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
$suffix = if ($Abi -eq 'armeabi-v7a') { '' } else { "-$Abi" }
if (!$SdkImage) { $SdkImage = "longreach-qt6-android-lollipop${suffix}:llvm21" }
if (!$OutputDirectory) { $OutputDirectory = "$repo/artifacts/qt6-android-lollipop$suffix" }
if ($Mode -in @('sdk','examples')) { Assert-AndroidNoEmulatorRunning -Message 'Stop the Android emulator before compiling.' }

 . "$repo/scripts/build/android-api21/artifact-lock.ps1"
$artifactLock=Enter-AndroidArtifactLock $OutputDirectory
try {
switch ($Mode) {
    'sdk' {
        . "$repo/scripts/build/android-api21/build-options.ps1"
        $buildFlags=@(Get-AndroidDockerBuildFlags -NoCache:$NoCache -DockerBuildFlagsJson $DockerBuildFlagsJson)
        # Fail before downloads or provisioning when the required ready host SDK is absent.
        Invoke-Qt6AndroidTool docker @('image','inspect',$HostImage) | Out-Null
        # This is the only mode allowed to fetch build inputs or build images.
        & "$repo/scripts/fetch/qt6-android.ps1" -AndroidSdk $AndroidSdk -Scope sdk -Abi $Abi
        $tools = 'longreach-qt4-android-donut:llvm21'
        Invoke-Qt6AndroidTool docker (@('build') + $buildFlags + @('--platform','linux/amd64','--file',
            "$repo/docker/qt4/android/Dockerfile",'--build-arg',"PARALLEL_JOBS=$ParallelJobs",'--tag',$tools,$repo))
        Invoke-Qt6AndroidTool docker (@('build') + $buildFlags + @('--platform','linux/amd64','--progress','plain',
            '--file',"$repo/docker/qt6/android/Dockerfile",'--build-arg',"PARALLEL_JOBS=$ParallelJobs",
            '--build-arg',"QT_HOST_IMAGE=$HostImage",'--build-arg',"ANDROID_ABI=$Abi",'--target','sdk','--tag',$SdkImage,$repo))
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
                $labels.'org.openkaryon.longreach-qt.platform' -ne "android-lollipop-$Abi" -or
                $labels.'org.openkaryon.longreach-qt.android-api' -ne '21' -or
                $labels.'org.openkaryon.longreach-qt.version' -ne '6.8.5' -or
                $labels.'org.openkaryon.longreach-qt.compiler' -ne 'LLVM 21.1.8') {
            throw "Image '$SdkImage' is not the Qt6.8.5 / LLVM21.1.8 Android API21 $Abi SDK."
        }
        $output = (New-Item -ItemType Directory -Path $OutputDirectory -Force).FullName
        & python "$repo/scripts/build/android-api21/artifact-manifest.py" begin --root $output --qt-major 6 --abi $Abi --sdk-image-id $image.Id --artifact-lease-held
        if ($LASTEXITCODE) { throw 'Cannot start an example generation' }
        # Pin this invocation to the inspected image even if its tag is retargeted.
        Invoke-Qt6AndroidTool docker @('run','--rm','--platform','linux/amd64','--cpus','2',
            '--memory','3g','--network','none','--env',"PARALLEL_JOBS=$ParallelJobs",'--env',"LONGREACH_SDK_IMAGE_ID=$($image.Id)",'--mount',"type=bind,source=$repo,target=/repo,readonly",
            '--mount',"type=bind,source=$output,target=/out",$image.Id,
            'bash','/repo/scripts/build/qt6-android/build-examples.sh')
        $image.Id | Set-Content -LiteralPath "$output/examples-sdk-image-id.txt"
        & python "$repo/scripts/build/android-api21/artifact-manifest.py" finish --root $output --qt-major 6 --abi $Abi --sdk-image-id $image.Id --artifact-lease-held
        if ($LASTEXITCODE) { throw 'Incomplete example generation' }
    }
    'package' {
        if (!$AndroidSdk) { throw 'Set ANDROID_HOME or pass -AndroidSdk for APK packaging.' }
        $AndroidSdk = (Resolve-Path -LiteralPath $AndroidSdk).Path
        $output = (Resolve-Path -LiteralPath $OutputDirectory).Path
        & "$PSScriptRoot/qt6-android/package-suite.ps1" -AndroidSdk $AndroidSdk -OutputDirectory $output -Abi $Abi
    }
    'test' {
        if (!$AndroidSdk) { throw 'Set ANDROID_HOME or pass -AndroidSdk for adb.' }
        $AndroidSdk = (Resolve-Path -LiteralPath $AndroidSdk).Path
        $output = (Resolve-Path -LiteralPath $OutputDirectory).Path
        $testOptions = @{}
        if ($DebugQtPlugins) { $testOptions.DebugQtPlugins = $true }
        & "$repo/scripts/run/qt6-android-suite.ps1" -AndroidSdk $AndroidSdk -OutputDirectory $output `
            -RunName $RunName -Gpu $Gpu -Abi $Abi -CaseNames $CaseNames -QtQuickBackend $QtQuickBackend @testOptions
    }
}

} finally { if ($artifactLock) { $artifactLock.Dispose() } }
