# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#Requires -Version 7.0
param([ValidateSet('sdk')][string]$Mode='sdk', [string]$SdkImage,
      [string]$InputDirectory, [string]$OutputDirectory,
      [ValidateRange(1,256)][int]$ParallelJobs=2,
      [switch]$NoCache, [string]$DockerBuildFlagsJson='[]')
$ErrorActionPreference='Stop'
$repo=(Resolve-Path "$PSScriptRoot/../../..").Path
. "$PSScriptRoot/host.ps1"
. "$repo/scripts/run/android/android-emulator-state.ps1"
. "$repo/scripts/build/android-api21/artifact-lock.ps1"
. "$repo/scripts/build/android-api21/build-options.ps1"
if (!$InputDirectory) { $InputDirectory="$repo/downloads/android-donut" }
if (!$OutputDirectory) { $OutputDirectory="$repo/artifacts/qt4-android-donut-sdk" }
if (!$SdkImage) { $SdkImage='longreach-qt4-android-donut-armeabi:llvm21' }
if ($SdkImage -ceq 'longreach-qt4-android-donut:llvm21') {
    throw 'The bootstrap tools tag is reserved; select a distinct installed SDK image'
}
$inputs=(Resolve-Path -LiteralPath $InputDirectory).Path
$flags=@(Get-AndroidDockerBuildFlags -NoCache:$NoCache -DockerBuildFlagsJson $DockerBuildFlagsJson)
Assert-AndroidNoEmulatorRunning -Message 'Stop the Android emulator before compiling the API4 SDK'
$root=(New-Item -ItemType Directory -Force -Path $OutputDirectory).FullName
$pending=Join-Path $root 'api4-sdk-in-progress.json'
if ((Test-Path -LiteralPath $pending) -or (Test-Path -LiteralPath "$root/sdk-image-id.txt")) {
    throw 'Preserve the previous SDK generation and choose a fresh output directory'
}
$lease=Enter-AndroidArtifactLock $root
$jobsFile=$null
$started=$false
try {
    if ((Test-Path -LiteralPath $pending) -or (Test-Path -LiteralPath "$root/sdk-image-id.txt")) {
        throw 'Preserve the previous SDK generation and choose a fresh output directory'
    }
    [IO.File]::WriteAllText($pending,(@{schema_version=1;status='building';sdk_image=$SdkImage} | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    $started=$true
    Invoke-DonutCommand python @("$PSScriptRoot/api4-sdk.py",'capture-source','--repo',$repo,'--input-directory',$inputs,'--snapshot',"$root/sdk-source-inputs.json")
    $jobsFile=New-AndroidBuildJobsFile $ParallelJobs
    Invoke-DonutCommand docker (@('build') + $flags + @('--platform','linux/amd64','--progress','plain','--target','api4-sdk',
        '--build-context',"android-api4-inputs=$inputs",'--secret',"id=longreach-jobs,src=$jobsFile",'--file',"$repo/docker/qt4/android/Dockerfile",'--tag',$SdkImage,$repo))
    Invoke-DonutCommand python @("$PSScriptRoot/api4-sdk.py",'compare-source','--repo',$repo,'--input-directory',$inputs,'--snapshot',"$root/sdk-source-inputs.json")
    $image=(Invoke-DonutCommand docker @('image','inspect','--format','{{json .}}',$SdkImage)) | ConvertFrom-Json
    $labels=$image.Config.Labels
    if ($image.Id -notmatch '^sha256:[0-9a-f]{64}$' -or $image.Os -ne 'linux' -or $image.Architecture -ne 'amd64' -or
        $labels.'org.openkaryon.longreach-qt.version' -ne '4.8.7' -or
        $labels.'org.openkaryon.longreach-qt.compiler' -ne 'LLVM 21.1.8' -or
        $labels.'org.openkaryon.longreach-qt.platform' -ne 'android-donut-armeabi' -or
        $labels.'org.openkaryon.longreach-qt.android-api' -ne '4') {
        throw 'The built image is not the installed Qt4 API4 armeabi SDK'
    }
    $container=((Invoke-DonutCommand docker @('create',$image.Id)) -join '').Trim()
    if ($container -notmatch '^[0-9a-f]{64}$') { throw 'Invalid SDK export container identity' }
    try {
        Invoke-DonutCommand docker @('cp',"${container}:/opt/qt4-android-armeabi-llvm/longreach-reports/api4-sdk.json","$root/sdk-manifest.json")
        Invoke-DonutCommand docker @('cp',"${container}:/opt/qt4-android-armeabi-llvm/longreach-reports/qmake-query.txt","$root/sdk-qmake-query.txt")
    } finally { Invoke-DonutCommand docker @('rm',$container) | Out-Null }
    $report=Get-Content -LiteralPath "$root/sdk-manifest.json" -Raw | ConvertFrom-Json
    if ($report.api -ne 4 -or $report.abi -ne 'armeabi' -or $report.qt -ne '4.8.7' -or $report.runtime_linkage -ne 'static') {
        throw 'Exported SDK report is not the API4 static SDK'
    }
    Invoke-DonutCommand python @("$PSScriptRoot/api4-sdk.py",'check-source-binding','--manifest',"$root/sdk-manifest.json",'--snapshot',"$root/sdk-source-inputs.json")
    $result=[ordered]@{schema_version=1;sdk_image=$SdkImage;sdk_image_id=$image.Id;
        sdk_manifest_sha256=(Get-FileHash "$root/sdk-manifest.json" -Algorithm SHA256).Hash.ToLowerInvariant();
        sdk_source_inputs_sha256=(Get-FileHash "$root/sdk-source-inputs.json" -Algorithm SHA256).Hash.ToLowerInvariant();
        qt='4.8.7';api=4;abi='armeabi';guest_qualification=$false}
    [IO.File]::WriteAllText("$root/sdk-generation.json",($result|ConvertTo-Json)+"`n",[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText("$root/sdk-image-id.txt",$image.Id+"`n",[Text.UTF8Encoding]::new($false))
    [IO.File]::Delete($pending)
    Write-Output 'Installed API4 SDK generation recorded; guest qualification is still separate'
} catch {
    if ($started -and (Test-Path -LiteralPath $pending)) {
        [IO.File]::WriteAllText($pending,(@{schema_version=1;status='failed';sdk_image=$SdkImage;error=$_.Exception.Message}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
    }
    throw
} finally {
    if ($jobsFile) { [IO.File]::Delete($jobsFile) }
    if ($lease) { $lease.Dispose() }
}
