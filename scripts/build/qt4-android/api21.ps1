# SPDX-License-Identifier: GPL-3.0-or-later
#Requires -Version 7.0
param([ValidateSet('x86','x86_64','arm64-v8a')][string]$Abi='x86_64',
      [ValidateSet('sdk','examples','package','test')][string]$Mode='examples',
      [string]$SdkImage, [string]$OutputDirectory, [string]$AndroidSdk=$env:ANDROID_HOME,
      [string]$RunName='sdk-suite', [string[]]$Profiles,
      [ValidateRange(1,256)][int]$ParallelJobs=2,
      [switch]$NoCache, [string]$DockerBuildFlagsJson='[]')
$ErrorActionPreference='Stop'
$Abi=$Abi.ToLowerInvariant()
$repo=(Resolve-Path "$PSScriptRoot/../../..").Path
. "$repo/scripts/run/android/android-emulator-state.ps1"
. "$PSScriptRoot/host.ps1"
function Invoke-Qt4Artifact([string[]]$Arguments) {
    $message=@(& python "$PSScriptRoot/artifact-manifest.py" @Arguments 2>&1)
    if ($LASTEXITCODE) { throw ($message -join "`n") }
    $message | Out-Host
}
if (!$AndroidSdk) { throw 'Set ANDROID_HOME or pass -AndroidSdk' }
$AndroidSdk=(Resolve-Path -LiteralPath $AndroidSdk).Path
$api=if ($Abi -eq 'x86') { 10 } else { 21 }
$platform=if ($api -eq 10) { 'gingerbread' } else { 'lollipop' }
if (!$OutputDirectory) { $OutputDirectory="$repo/artifacts/qt4-android-$platform-$Abi" }
if (!$SdkImage) { $SdkImage="longreach-qt4-android-$platform-${Abi}:llvm21" }
$root=(New-Item -ItemType Directory -Force -Path $OutputDirectory).FullName
$prefix="/opt/qt4-android-$Abi-llvm"
$allProfiles=@('bootstrap','strict','core','selftest','widgets','graphics','painting','multimedia','gl','qml','network','quick')
if ($Mode -in @('sdk','examples')) { Assert-AndroidNoEmulatorRunning -Message 'Stop the Android emulator before compiling' }
. "$repo/scripts/build/android-api21/artifact-lock.ps1"
$jobsFile=$null
$artifactLock=Enter-AndroidArtifactLock $root
try {
switch ($Mode) {
    'sdk' {
        Clear-AndroidResultAggregates $root
        . "$repo/scripts/build/android-api21/build-options.ps1"
        $buildFlags=@(Get-AndroidDockerBuildFlags -NoCache:$NoCache -DockerBuildFlagsJson $DockerBuildFlagsJson)
        $jobsFile=New-AndroidBuildJobsFile $ParallelJobs
        & "$repo/scripts/fetch/qt4-android.ps1" -Abi $Abi -Scope sdk -AndroidSdk $AndroidSdk
        Invoke-DonutCommand docker (@('build') + $buildFlags + @('--platform','linux/amd64','--progress','plain','--target','sdk',
            '--build-arg',"ANDROID_ABI=$Abi",'--secret',"id=longreach-jobs,src=$jobsFile",'--file',"$repo/docker/qt4/android/Dockerfile",'--tag',$SdkImage,$repo))
        Invoke-DonutCommand docker @('image','inspect','--format','{{.Id}}',$SdkImage) | Set-Content "$root/sdk-image-id.txt"
    }
    'examples' {
        $image=(Invoke-DonutCommand docker @('image','inspect','--format','{{json .}}',$SdkImage)) | ConvertFrom-Json
        $labels=$image.Config.Labels
        if ($image.Os -ne 'linux' -or $image.Architecture -ne 'amd64' -or
                $labels.'org.openkaryon.longreach-qt.version' -ne '4.8.7' -or
                $labels.'org.openkaryon.longreach-qt.compiler' -ne 'LLVM 21.1.8' -or
                $labels.'org.openkaryon.longreach-qt.android-api' -ne "$api" -or
                $labels.'org.openkaryon.longreach-qt.platform' -ne "android-$platform-$Abi") {
            throw "Image '$SdkImage' is not the Qt4.8.7/LLVM21.1.8 API$api $Abi SDK"
        }
        . "$PSScriptRoot/client-cache.ps1"
        $clientCache=Get-Qt4ClientCacheIdentity $root $Abi
        Assert-Qt4ClientCacheIdle $clientCache
        Invoke-Qt4Artifact @('begin','--root',$root,'--abi',$Abi,'--sdk-image-id',$image.Id,'--artifact-lease-held')
        $native=(New-Item -ItemType Directory -Force "$root/native").FullName
        $reports=(New-Item -ItemType Directory -Force "$root/sdk-reports").FullName
        $export=((Invoke-DonutCommand docker @('create',$image.Id)) -join '').Trim()
        if ($export -notmatch '^[0-9a-f]{64}$') { throw 'Invalid SDK export container identity' }
        try {
            . "$repo/scripts/build/android-api21/sdk-reports.ps1"
            Import-AndroidSdkReports -Container $export -ProducerDirectory "$prefix/longreach-reports" -OutputDirectory $reports -QtMajor 4 -Api $api -Abi $Abi -SdkImageId $image.Id
        }
        finally { Invoke-DonutCommand docker @('rm',$export) | Out-Null }
        $image.Id | Set-Content "$root/sdk-image-id.txt"
        Invoke-DonutCommand docker @('run','--rm','--name',$clientCache.Container,'--init','--platform','linux/amd64','--cpus','2','--memory','3g','--network','none','--env',"PARALLEL_JOBS=$ParallelJobs",
            '--mount',"type=bind,source=$repo,target=/repo,readonly",'--mount',"type=bind,source=$native,target=/out",'--mount',"type=volume,source=$($clientCache.Volume),target=/work",
            '--env',"LONGREACH_SDK_IMAGE_ID=$($image.Id)",$image.Id,'bash','/repo/scripts/build/qt4-android/build-api21-examples.sh','all')
        Invoke-Qt4Artifact @('finish','--root',$root,'--abi',$Abi,'--sdk-image-id',$image.Id,'--artifact-lease-held')
    }
    'package' {
        Clear-AndroidResultAggregates $root
        Invoke-Qt4Artifact @('check-examples','--root',$root,'--abi',$Abi,'--artifact-lease-held')
        $built=@((Get-Content "$root/native/examples-build.json" -Raw | ConvertFrom-Json).clients)
        $nativePaths=@($built | ForEach-Object { "$root/native/$($_.native)" }) + @("$root/native/libc++_shared.so")
        & python "$repo/scripts/build/android-api21/native-abi.py" --abi $Abi @nativePaths
        if ($LASTEXITCODE) { throw 'Native ABI preflight failed' }
        $jar=(Get-Item "$AndroidSdk/platforms/android-35/android.jar").FullName
        $lock=Get-Content "$repo/scripts/fetch/locks/qt6-android-api21-inputs.json" -Raw | ConvertFrom-Json
        $jarHash=($lock.sources | Where-Object { $_.file -eq 'android-35.jar' }).sha256
        if ((Get-FileHash $jar -Algorithm SHA256).Hash.ToLowerInvariant() -ne $jarHash) { throw 'Unpinned Android35 packaging jar' }
        $javaTools=Get-AndroidPackagingJava
        Initialize-DonutSigningKey $root (Split-Path $javaTools.javac) | Out-Null
        Invoke-Qt4Artifact @('begin-apks','--root',$root,'--abi',$Abi,'--android-sdk',$AndroidSdk,'--javac',$javaTools.launcher,'--artifact-lease-held')
        foreach ($profile in $allProfiles) {
            & "$PSScriptRoot/package.ps1" -Abi $Abi -Profile $profile -NativeDirectory "$root/native" `
                -OutputDirectory $root -AndroidSdk $AndroidSdk -AndroidJar $jar -JavaTools $javaTools
        }
        Invoke-Qt4Artifact @('record-apks','--root',$root,'--abi',$Abi,'--android-sdk',$AndroidSdk,'--javac',$javaTools.launcher,'--artifact-lease-held')
    }
    'test' {
        Invoke-Qt4Artifact @('check-apks','--root',$root,'--abi',$Abi,'--artifact-lease-held')
        $options=@{Abi=$Abi;AndroidSdk=$AndroidSdk;OutputDirectory=$root;RunName=$RunName}
        if ($Profiles) { $options.Profiles=$Profiles }
        & "$repo/scripts/run/qt4-android-api21-suite.ps1" @options
    }
}

} finally {
    if ($jobsFile) { [IO.File]::Delete($jobsFile) }
    if ($artifactLock) { $artifactLock.Dispose() }
}
