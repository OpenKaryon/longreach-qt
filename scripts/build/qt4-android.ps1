# SPDX-License-Identifier: GPL-3.0-or-later
#Requires -Version 7.0

param(
    [ValidateSet('armeabi','x86','x86_64','arm64-v8a')][string]$Abi='armeabi',
    [ValidateSet('sdk','examples','package','test')][string]$Mode='examples',
    [string]$SdkImage,
    [string]$RunName='sdk-suite',
    [string[]]$Profiles,
    [string] $InputDirectory,
    [string] $OutputDirectory,
    [string] $AndroidSdk = $env:ANDROID_HOME,
    [ValidateRange(1,256)][int]$ParallelJobs=2,
    [switch]$NoCache,
    [string]$DockerBuildFlagsJson='[]'
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
. "$repo/scripts/run/android-emulator-state.ps1"
. "$PSScriptRoot/qt4-android/host.ps1"

if ($Abi -ne 'armeabi') {
    if ($InputDirectory) { throw '-InputDirectory is only for the original API4 inputs' }
    $options=@{} + $PSBoundParameters
    $options.Remove('InputDirectory') | Out-Null
    $options.Mode=$Mode
    & "$PSScriptRoot/qt4-android/api21.ps1" @options
    return
}
foreach ($option in @('Mode','SdkImage','RunName','Profiles','ParallelJobs','NoCache','DockerBuildFlagsJson')) {
    if ($PSBoundParameters.ContainsKey($option)) { throw "-$option is currently supported by the API10/API21 profiles only" }
}

if (!$InputDirectory) { $InputDirectory = Join-Path $repo 'downloads/android-donut' }
if (!$OutputDirectory) { $OutputDirectory = Join-Path $repo 'artifacts/qt4-android-donut' }
if (!$AndroidSdk) { throw 'Set ANDROID_HOME or pass -AndroidSdk.' }
$AndroidSdk = (Resolve-Path -LiteralPath $AndroidSdk).Path
$inputs = (Resolve-Path -LiteralPath $InputDirectory).Path
$output = (New-Item -ItemType Directory -Force -Path $OutputDirectory).FullName
. "$PSScriptRoot/android-api21/artifact-lock.ps1"
. "$repo/scripts/run/android-owned-process.ps1"
Assert-AndroidOwnedArtifactRootAvailable $output
$artifactLock=Enter-AndroidArtifactLock $output
try {
function Invoke-DonutArtifact([string[]]$Arguments) {
    Invoke-DonutCommand python (@("$PSScriptRoot/qt4-android/donut-artifacts.py") + $Arguments + @('--artifact-lease-held'))
}
$llvm = (Get-Item -LiteralPath "$repo/downloads/llvm-project-21.1.8.src.tar.xz").FullName
$qt = (Get-Item -LiteralPath "$repo/downloads/qt-everywhere-opensource-src-4.8.7.tar.gz").FullName
$sysroot = (Get-Item -LiteralPath "$inputs/aosp-ndk-r7-api4-arm.tar.gz").FullName

Assert-AndroidNoEmulatorRunning -Message 'Stop the Android emulator before starting the SDK build.'

Invoke-DonutArtifact @('begin','--root',$output,'--repo',$repo,'--input-directory',$inputs)
$nativeWork=(New-Item -ItemType Directory -Path (Join-Path $output ('native-build-'+[guid]::NewGuid().ToString('N')))).FullName
$api4 = Expand-DonutInput "$inputs/android-1.6_r03-linux.zip" `
    'a8c4e3b32269c6b04c2adeabd112fce42f292dab1a40ef3b08ea7d4212be0df4' `
    (Join-Path $output 'inputs') 'android-1.6_r03-linux/android.jar'
$image = 'longreach-qt4-android-donut:llvm21'
Invoke-DonutCommand docker @('build', '--platform', 'linux/amd64', '--file', "$repo/docker/qt4/android/Dockerfile", '--build-arg', 'PARALLEL_JOBS=2', '--tag', $image, $repo)
$imageId=((Invoke-DonutCommand docker @('image','inspect','--format','{{.Id}}',$image)) -join '').Trim()
if ($imageId -notmatch '^sha256:[0-9a-f]{64}$') { throw 'Missing immutable API4 tool image identity' }
Invoke-DonutCommand docker @(
    'run', '--rm', '--platform', 'linux/amd64', '--cpus', '2', '--memory', '3g', '--network', 'none',
    '--mount', "type=bind,source=$repo,target=/repo,readonly",
    '--mount', "type=bind,source=$llvm,target=/inputs/llvm-project-21.1.8.src.tar.xz,readonly",
    '--mount', "type=bind,source=$qt,target=/inputs/qt-everywhere-opensource-src-4.8.7.tar.gz,readonly",
    '--mount', "type=bind,source=$sysroot,target=/inputs/aosp-ndk-r7-api4-arm.tar.gz,readonly",
    '--mount', "type=bind,source=$nativeWork,target=/out",
    '--workdir', '/work', $imageId, 'bash', '/repo/scripts/build/qt4-android/build-native.sh'
)

Invoke-DonutArtifact @('finish-native','--root',$output,'--repo',$repo,'--input-directory',$inputs,'--native-directory',$nativeWork,'--tool-image-id',$imageId)
$native=Join-Path $output 'native'
$javaTools=Get-AndroidPackagingJava
Initialize-DonutSigningKey $output (Split-Path $javaTools.javac) | Out-Null
Invoke-DonutArtifact @('begin-apks','--root',$output,'--android-sdk',$AndroidSdk,'--android-jar',$api4,'--javac',$javaTools.launcher)
foreach ($profile in 'bootstrap', 'strict', 'core', 'quick', 'selftest', 'graphics', 'network', 'painting') {
    & "$PSScriptRoot/qt4-android/package.ps1" -Profile $profile -NativeDirectory $native `
        -OutputDirectory $output -AndroidSdk $AndroidSdk -AndroidJar $api4 -JavaTools $javaTools
}
Invoke-DonutArtifact @('record-apks','--root',$output,'--android-sdk',$AndroidSdk,'--android-jar',$api4,'--javac',$javaTools.launcher)
} finally { if ($artifactLock) { $artifactLock.Dispose() } }
