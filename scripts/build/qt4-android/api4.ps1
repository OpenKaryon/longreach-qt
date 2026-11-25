# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#Requires -Version 7.0
param([ValidateSet('sdk','examples','package','test')][string]$Mode='sdk', [string]$SdkImage,
      [string]$InputDirectory, [string]$OutputDirectory, [string]$AndroidSdk=$env:ANDROID_HOME,
      [ValidateSet('bootstrap','strict','core','quick','selftest','graphics','network','painting')][string[]]$Profiles,
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
if ($Mode -eq 'sdk') {
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
    return
}

if ($Mode -eq 'examples') { Assert-AndroidNoEmulatorRunning -Message 'Stop the Android emulator before compiling API4 examples' }
$root=(New-Item -ItemType Directory -Force -Path $OutputDirectory).FullName
. "$repo/scripts/run/android/android-owned-process.ps1"
Assert-AndroidOwnedArtifactRootAvailable $root
$lease=Enter-AndroidArtifactLock $root
function Invoke-Api4Artifact([string[]]$Arguments) {
    Invoke-DonutCommand python (@("$PSScriptRoot/donut-artifacts.py")+$Arguments+@('--artifact-lease-held'))
}
try {
    switch ($Mode) {
        'examples' {
            . "$PSScriptRoot/client-cache.ps1"
            $client=Get-Qt4ClientCacheIdentity $root 'armeabi'
            Assert-Qt4ClientCacheIdle $client
            $image=((Invoke-DonutCommand docker @('image','inspect','--format','{{.Id}}',$SdkImage)) -join '').Trim()
            if ($image -notmatch '^sha256:[0-9a-f]{64}$') { throw 'Invalid API4 SDK image identity' }
            Invoke-Api4Artifact @('begin','--root',$root,'--repo',$repo,'--input-directory',$inputs,'--sdk-image-id',$image)
            $stage=(New-Item -ItemType Directory -Path "$root/native-build-$([guid]::NewGuid().ToString('N'))").FullName
            Invoke-DonutCommand docker @('run','--rm','--name',$client.Container,'--init','--platform','linux/amd64','--cpus','2','--memory','3g','--network','none',
                '--mount',"type=bind,source=$repo,target=/repo,readonly",'--mount',"type=bind,source=$stage,target=/out",
                '--workdir','/work',$image,'bash','/repo/scripts/build/qt4-android/build-api4-examples.sh')
            Assert-Qt4ClientCacheIdle $client
            Invoke-Api4Artifact @('finish-native','--root',$root,'--repo',$repo,'--input-directory',$inputs,'--native-directory',$stage,'--tool-image-id',$image)
        }
        'package' {
            Invoke-Api4Artifact @('check-native','--root',$root,'--installed-sdk')
            if (!$AndroidSdk) { throw 'Set ANDROID_HOME or pass -AndroidSdk' }
            $AndroidSdk=(Resolve-Path -LiteralPath $AndroidSdk).Path
            $jar=Expand-DonutInput "$inputs/android-1.6_r03-linux.zip" `
                'a8c4e3b32269c6b04c2adeabd112fce42f292dab1a40ef3b08ea7d4212be0df4' "$root/inputs" 'android-1.6_r03-linux/android.jar'
            $javaTools=Get-AndroidPackagingJava
            Initialize-DonutSigningKey $root (Split-Path $javaTools.javac) | Out-Null
            Invoke-Api4Artifact @('begin-apks','--root',$root,'--android-sdk',$AndroidSdk,'--android-jar',$jar,'--javac',$javaTools.launcher)
            foreach ($profile in 'bootstrap','strict','core','quick','selftest','graphics','network','painting') {
                & "$PSScriptRoot/package.ps1" -Profile $profile -NativeDirectory "$root/native" `
                    -OutputDirectory $root -AndroidSdk $AndroidSdk -AndroidJar $jar -JavaTools $javaTools
            }
            Invoke-Api4Artifact @('record-apks','--root',$root,'--android-sdk',$AndroidSdk,'--android-jar',$jar,'--javac',$javaTools.launcher)
        }
        'test' {
            Invoke-Api4Artifact @('check-native','--root',$root,'--installed-sdk')
            Invoke-Api4Artifact @('check-apks','--root',$root)
            $options=@{InputDirectory=$inputs;OutputDirectory=$root;AndroidSdk=$AndroidSdk}
            if ($Profiles) { $options.Profiles=$Profiles }
            & "$repo/scripts/run/qt4-android-donut.ps1" @options
        }
    }
} finally { if ($lease) { $lease.Dispose() } }
