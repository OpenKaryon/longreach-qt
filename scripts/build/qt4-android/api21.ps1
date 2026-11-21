# SPDX-License-Identifier: GPL-3.0-or-later
param([ValidateSet('x86','x86_64','arm64-v8a')][string]$Abi='x86_64',
      [ValidateSet('sdk','examples','package','test')][string]$Mode='examples',
      [string]$SdkImage, [string]$OutputDirectory, [string]$AndroidSdk=$env:ANDROID_HOME,
      [string]$RunName='sdk-suite', [string[]]$Profiles)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path "$PSScriptRoot/../../..").Path
. "$PSScriptRoot/host.ps1"
if (!$AndroidSdk) { throw 'Set ANDROID_HOME or pass -AndroidSdk' }
$AndroidSdk=(Resolve-Path -LiteralPath $AndroidSdk).Path
$api=if ($Abi -eq 'x86') { 10 } else { 21 }
$platform=if ($api -eq 10) { 'gingerbread' } else { 'lollipop' }
if (!$OutputDirectory) { $OutputDirectory="$repo/artifacts/qt4-android-$platform-$Abi" }
if (!$SdkImage) { $SdkImage="longreach-qt4-android-$platform-${Abi}:llvm21" }
$root=(New-Item -ItemType Directory -Force -Path $OutputDirectory).FullName
$prefix="/opt/qt4-android-$Abi-llvm"
$allProfiles=@('bootstrap','strict','core','selftest','widgets','graphics','painting','multimedia','gl','qml','network','quick')
if ($Mode -in @('sdk','examples') -and (Get-Process -Name emulator,emulator-arm,emulator-x86,emulator64-x86,emulator-ranchu-arm64,emulator64-ranchu-arm64,qemu-system-armel,qemu-system-x86_64,qemu-system-x86_64-headless,qemu-system-aarch64 -ErrorAction SilentlyContinue)) {
    throw 'Stop the Android emulator before compiling'
}
switch ($Mode) {
    'sdk' {
        & "$repo/scripts/fetch/qt4-android.ps1" -Abi $Abi -Scope sdk -AndroidSdk $AndroidSdk
        Invoke-DonutCommand docker @('build','--platform','linux/amd64','--progress','plain','--target','sdk',
            '--build-arg',"ANDROID_ABI=$Abi",'--file',"$repo/docker/qt4/android/Dockerfile",'--tag',$SdkImage,$repo)
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
        $native=(New-Item -ItemType Directory -Force "$root/native").FullName
        $reports=(New-Item -ItemType Directory -Force "$root/sdk-reports").FullName
        $export=((Invoke-DonutCommand docker @('create',$image.Id)) -join '').Trim()
        if ($export -notmatch '^[0-9a-f]{64}$') { throw 'Invalid SDK export container identity' }
        try { Invoke-DonutCommand docker @('cp',"${export}:${prefix}/longreach-reports/.",$reports) }
        finally { Invoke-DonutCommand docker @('rm',$export) | Out-Null }
        $image.Id | Set-Content "$root/sdk-image-id.txt"
        Invoke-DonutCommand docker @('run','--rm','--platform','linux/amd64','--cpus','2','--memory','3g','--network','none',
            '--mount',"type=bind,source=$repo,target=/repo,readonly",'--mount',"type=bind,source=$native,target=/out",
            $image.Id,'bash','/repo/scripts/build/qt4-android/build-api21-examples.sh','all')
        $image.Id | Set-Content "$root/examples-sdk-image-id.txt"
    }
    'package' {
        $sdkId=(Get-Content "$root/sdk-image-id.txt" -Raw).Trim()
        if ($sdkId -notmatch '^sha256:[0-9a-f]{64}$' -or
                (Get-Content "$root/examples-sdk-image-id.txt" -Raw).Trim() -ne $sdkId) { throw 'SDK/example identities differ' }
        $built=@(Get-Content "$root/native/examples-build.json" -Raw | ConvertFrom-Json)
        if ($built.Count -ne $allProfiles.Count -or @($built.profile | Sort-Object -Unique).Count -ne $allProfiles.Count -or
                @($allProfiles | Where-Object { $_ -notin $built.profile }).Count) { throw 'Expected all twelve Qt4 JNI clients' }
        foreach ($item in $built) {
            if ($item.native -ne "$($item.profile).so" -or
                    (Get-FileHash -LiteralPath "$root/native/$($item.native)" -Algorithm SHA256).Hash.ToLowerInvariant() -ne $item.sha256) {
                throw "Native artifact differs from example build: $($item.profile)"
            }
        }
        $jar=(Get-Item "$AndroidSdk/platforms/android-35/android.jar").FullName
        $lock=Get-Content "$repo/scripts/fetch/locks/qt6-android-api21-inputs.json" -Raw | ConvertFrom-Json
        $jarHash=($lock.sources | Where-Object { $_.file -eq 'android-35.jar' }).sha256
        if ((Get-FileHash $jar -Algorithm SHA256).Hash.ToLowerInvariant() -ne $jarHash) { throw 'Unpinned Android35 packaging jar' }
        $packages=[Collections.Generic.List[object]]::new()
        foreach ($profile in $allProfiles) {
            & "$PSScriptRoot/package.ps1" -Abi $Abi -Profile $profile -NativeDirectory "$root/native" `
                -OutputDirectory $root -AndroidSdk $AndroidSdk -AndroidJar $jar
            $packages.Add([pscustomobject]@{profile=$profile;apk="$profile.apk";abi=$Abi;api=$api;sdk_image_id=$sdkId;
                sha256=(Get-FileHash "$root/$profile.apk" -Algorithm SHA256).Hash.ToLowerInvariant()})
        }
        $packages | ConvertTo-Json -Depth 5 | Set-Content "$root/apk-packages.json"
    }
    'test' {
        $options=@{Abi=$Abi;AndroidSdk=$AndroidSdk;OutputDirectory=$root;RunName=$RunName}
        if ($Profiles) { $options.Profiles=$Profiles }
        & "$repo/scripts/run/qt4-android-api21-suite.ps1" @options
    }
}
