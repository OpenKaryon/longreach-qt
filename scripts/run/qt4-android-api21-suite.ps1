# SPDX-License-Identifier: GPL-3.0-or-later
param([ValidateSet('x86','x86_64','arm64-v8a')][string]$Abi='x86_64',
      [ValidateSet('bootstrap','strict','core','quick','selftest','graphics','network','painting','widgets','multimedia','gl','qml')][string[]]$Profiles,
      [string]$RunName='sdk-suite', [string]$AndroidSdk=$env:ANDROID_HOME, [string]$OutputDirectory)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/android-emulator-state.ps1"
$repo=(Resolve-Path "$PSScriptRoot/../..").Path
. "$PSScriptRoot/android-api21-log.ps1"
. "$PSScriptRoot/android-api21-adb.ps1"
. "$PSScriptRoot/android-wait-boot.ps1"
. "$PSScriptRoot/android-cpu.ps1"
. "$PSScriptRoot/android-owned-process.ps1"
$api=if ($Abi -eq 'x86') { 10 } else { 21 }
$platform=if ($api -eq 10) { 'gingerbread' } else { 'lollipop' }
$release=if ($api -eq 10) { '2.3.7' } else { '5.0.2' }
if ($RunName -notmatch '^[a-z0-9-]+$') { throw 'Invalid run directory name' }
if (!$AndroidSdk) { throw 'Set ANDROID_HOME or pass -AndroidSdk' }
if (!$OutputDirectory) { $OutputDirectory="$repo/artifacts/qt4-android-$platform-$Abi" }
$root=(Resolve-Path -LiteralPath $OutputDirectory).Path
. "$repo/scripts/build/android-api21/artifact-lock.ps1"
$artifactLock=Enter-AndroidArtifactLock $root
try {
Clear-AndroidResultAggregates $root
& python "$repo/scripts/build/qt4-android/artifact-manifest.py" check-apks --root $root --abi $Abi --artifact-lease-held
if ($LASTEXITCODE) { throw 'Refusing incomplete or mismatched Qt4 APK/native generation' }
$apkGenerationSha=(Get-FileHash -LiteralPath "$root/apk-manifest.json" -Algorithm SHA256).Hash.ToLowerInvariant()
$examplesManifestSha=(Get-FileHash -LiteralPath "$root/examples-manifest.json" -Algorithm SHA256).Hash.ToLowerInvariant()
$adb=(Get-Item "$AndroidSdk/platform-tools/adb.exe").FullName
$serial=if ($api -eq 10) { 'emulator-5580' } else { 'emulator-5582' }
$requiredProfiles=@('bootstrap','strict','core','selftest','widgets','graphics','painting','multimedia','gl','qml','network','quick')
$fullRun=!$Profiles
if (!$Profiles) { $Profiles=$requiredProfiles }
if (@($Profiles | Sort-Object -Unique).Count -ne $Profiles.Count) { throw 'Duplicate Qt4 test profile' }
$apkManifestSha=(Get-FileHash -LiteralPath "$root/apk-packages.json" -Algorithm SHA256).Hash.ToLowerInvariant()
$generationInputs=[ordered]@{
    'apk-packages.json'=$apkManifestSha
    'apk-manifest.json'=$apkGenerationSha
    'examples-manifest.json'=$examplesManifestSha
    'sdk-image-id.txt'=(Get-FileHash -LiteralPath "$root/sdk-image-id.txt" -Algorithm SHA256).Hash.ToLowerInvariant()
    'examples-sdk-image-id.txt'=(Get-FileHash -LiteralPath "$root/examples-sdk-image-id.txt" -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Assert-Qt4RunGeneration {
    foreach ($name in $generationInputs.Keys) {
        Get-AndroidVerifiedHash (Join-Path $root $name) $generationInputs[$name] | Out-Null
    }
}
$packages=@(Get-Content "$root/apk-packages.json" -Raw | ConvertFrom-Json)
$sdkId=(Get-Content "$root/sdk-image-id.txt" -Raw).Trim()
Assert-Qt4RunGeneration
if ($sdkId -notmatch '^sha256:[0-9a-f]{64}$' -or (Get-Content "$root/examples-sdk-image-id.txt" -Raw).Trim() -ne $sdkId) { throw 'SDK/example identities differ' }
foreach ($profile in $Profiles) {
    $package=@($packages | Where-Object { $_.profile -eq $profile })
    if ($package.Count -ne 1 -or $package[0].abi -ne $Abi -or $package[0].api -ne $api -or $package[0].sdk_image_id -ne $sdkId -or
            $package[0].apk -ne "$profile.apk" -or (Get-FileHash "$root/$profile.apk" -Algorithm SHA256).Hash.ToLowerInvariant() -ne $package[0].sha256) {
        throw "APK does not match the current SDK/package manifest: $profile"
    }
}
$quickChecks=@('PASS: qrc and first frame','PASS: Android tap updates QML and frame',
    'PASS: Android pause and resume preserve input and rendering',
    'PASS: shared Qt Quick Gallery renders and navigates',
    'PASS: shared Widgets Gallery toggles a checkbox and changes tabs')
$labels=@{selftest='qt-selftest';widgets='widgets-gallery';graphics='graphics';painting='painting-lab';multimedia='multimedia-lab';gl='gl-heavy';qml='quick-qml';network='network-gui'}
Assert-AndroidNoEmulatorRunning -Message 'Stop the existing emulator before this suite'
foreach ($profile in $Profiles) { if (!(Test-Path "$root/$profile.apk")) { throw "Missing APK: $profile" } }
function Invoke-Adb {
    param([string[]]$Arguments,[switch]$AllowNonzero)
    Invoke-AndroidApi21Adb -Adb $adb -Serial $serial -Parameters $Arguments -AllowNonzero:$AllowNonzero
}
& "$repo/scripts/fetch/qt4-android.ps1" -Scope test -Abi $Abi -AndroidSdk $AndroidSdk
if ($api -eq 21) {
    & python "$repo/scripts/build/qt6-android/prepare-emulator.py" --repo $repo --output $root --abi $Abi
    if ($LASTEXITCODE) { throw 'Cannot prepare pinned API21 guest' }
    $emulator=if ($Abi -eq 'arm64-v8a') { "$root/media/emulator-25.2.5/tools/emulator.exe" }
        else { "$root/media/emulator-32.1.11/emulator/emulator.exe" }
    $emulatorOwner=& "$PSScriptRoot/qt6-android-start.ps1" -OutputDirectory $root -Abi $Abi -RunName $RunName -Emulator $emulator -PassThru
} else {
    $running = & docker ps --filter status=running --filter label=org.openkaryon.longreach-qt.android-api=10 --format '{{.Names}}'
    if ($LASTEXITCODE) { throw 'Cannot verify that the build slot is free' }
    if ($running) { throw 'Stop the API10 native builder before starting the emulator' }
    $media=(New-Item -ItemType Directory -Force "$root/media").FullName
    & tar.exe -xf "$repo/downloads/android-gingerbread/x86-10_r05.zip" -C $media
    if ($LASTEXITCODE) { throw 'Cannot extract API10 x86 image' }
    & tar.exe -xf "$repo/downloads/android-gingerbread/tools_r24.4.1-windows.zip" -C $media
    if ($LASTEXITCODE) { throw 'Cannot extract legacy emulator' }
    $run="$root/$RunName"
    if (Test-Path -LiteralPath $run) { throw 'Archive the previous run before starting a fresh one' }
    New-Item -ItemType Directory -Path $run | Out-Null
    Copy-Item -LiteralPath "$media/x86/userdata.img" -Destination "$run/userdata-qemu.img"
    $arguments=@('-sysdir',"$media/x86",'-datadir',$run,'-system',"$media/x86/system.img",
        '-kernel',"$media/x86/kernel-qemu",'-ramdisk',"$media/x86/ramdisk.img",
        '-data',"$run/userdata-qemu.img",'-initdata',"$media/x86/userdata.img",
        '-no-window','-no-audio','-no-snapshot','-no-snapstorage','-skin','480x320',
        '-partition-size','512','-memory','256','-gpu','on','-port','5580',
        '-no-boot-anim','-verbose','-show-kernel','-no-accel','-qemu','-cpu','core2duo')
    Write-AndroidOwnedProcessJson "$run/emulator-launch.json" @{schema_version=1;abi=$Abi;emulator="$media/tools/emulator-x86.exe";arguments=@($arguments)}
    # The direct legacy backend does not add its GLES translator DLL directory.
    $previousPath=$env:PATH
    try {
        $env:PATH="$media/tools/lib;$previousPath"
        $emulatorOwner=Start-AndroidOwnedProcess -Program "$media/tools/emulator-x86.exe" -Arguments $arguments -Directory $run -ArtifactRoot $root -ArtifactLease (Get-AndroidArtifactLockStream $root) -AdbEndpoint (Get-AndroidAdbEndpoint)
    } finally { $env:PATH=$previousPath }
}
$run="$root/$RunName"
$outcomes=[Collections.Generic.List[object]]::new()
$emulatorIdentitySha=$null
$emulatorMediaSha=$null
$hostTree=$null
try {
    if ($api -eq 21) {
        $emulatorIdentitySha=(Get-FileHash "$run/emulator-identity.json").Hash.ToLowerInvariant()
        $emulatorMediaSha=(Get-FileHash "$run/emulator-media.json").Hash.ToLowerInvariant()
    }
    Wait-AndroidBoot -Adb $adb -Serial $serial -RunDirectory $run -EmulatorPid $emulatorOwner.Process.Id -EmulatorProcess $emulatorOwner.Process -TimeoutSeconds 300
    foreach ($pair in @(@('ro.build.version.sdk',"$api"),@('ro.build.version.release',$release),@('ro.product.cpu.abi',$Abi))) {
        $actual=((Invoke-Adb @('shell','getprop',$pair[0])) -join '').Trim()
        if ($actual -ne $pair[1]) { throw "Wrong guest: $($pair[0])=$actual" }
    }
    Invoke-Adb @('shell','getprop') | Set-Content "$run/guest-properties.txt"
    Invoke-Adb @('shell','cat','/proc/cpuinfo') | Set-Content "$run/guest-cpuinfo.txt"
    $guestCpu=Save-AndroidGuestCpuBaseline $run $Abi
    Invoke-Adb @('shell','input','keyevent','82') | Out-Null
    foreach ($profile in $Profiles) {
        $case=(New-Item -ItemType Directory -Path "$run/$profile").FullName
        $package=if ($profile -eq 'quick') { 'org.longreachqt.donut.quick' } else { 'org.longreachqt.donut' }
        $apk="$root/$profile.apk"
        $recordedPackage=@($packages | Where-Object { $_.profile -eq $profile })
        Assert-Qt4RunGeneration
        $installedApkSha=Get-AndroidVerifiedHash $apk ($recordedPackage[0].sha256)
        $installed=Invoke-Adb @('install','-r',$apk)
        $installed | Set-Content "$case/install.txt"
        if (!($installed -match '^\s*Success\s*$')) { throw "APK install failed: $profile" }
        Get-AndroidVerifiedHash $apk $installedApkSha | Out-Null
        Assert-Qt4RunGeneration
        Invoke-Adb @('shell','am','force-stop',$package) | Out-Null
        $clear=Invoke-Adb @('shell','pm','clear',$package)
        if (!($clear -match '^\s*Success\s*$')) { throw 'Could not reset app data' }
        if ($api -eq 21) { Invoke-Adb @('logcat','-b','all','-c') | Out-Null }
        else { Invoke-Adb @('logcat','-c') | Out-Null }
        $marker='BEGIN-'+[guid]::NewGuid().ToString('N')
        $marker | Set-Content "$case/log-marker.txt"
        Invoke-Adb @('shell','log','-p','i','-t','LongreachCase',$marker) | Out-Null
        $complete=$false
        $native=@()
        Get-AndroidVerifiedHash $apk $installedApkSha | Out-Null
        Assert-Qt4RunGeneration
        if ($profile -eq 'quick') {
            $instrument=$null
            try {
                $instrument=Start-Process -FilePath $adb -WindowStyle Hidden -PassThru `
                    -ArgumentList @(Get-AndroidAdbArguments -Arguments @('-s',$serial,'shell','am','instrument','-w',"$package/.QuickInstrumentation") -Directory $run) `
                    -RedirectStandardOutput "$case/instrumentation.log" -RedirectStandardError "$case/instrumentation.stderr"
                if (!$instrument.WaitForExit(120000)) { throw 'Qt4 gallery instrumentation timed out' }
                $text=Get-Content "$case/instrumentation.log"
                if ($instrument.ExitCode -ne 0 -or !($text -match '^INSTRUMENTATION_CODE: -1\s*$')) { throw 'Qt4 gallery instrumentation failed' }
            } finally {
                if ($instrument) {
                    try {
                        if (!$instrument.HasExited) {
                            Stop-Process -InputObject $instrument -ErrorAction SilentlyContinue
                            if (!$instrument.WaitForExit(1000)) { throw 'Owned Qt4 instrumentation client did not stop' }
                        }
                    } finally { $instrument.Dispose() }
                }
            }
            $complete=$true
            $native=@('0')
        } else {
            Invoke-Adb @('shell','am','start','-n',"$package/.ProbeActivity") | Set-Content "$case/launch.txt"
            for ($attempt=0; $attempt -lt 90; $attempt++) {
                Start-Sleep -Seconds 2
                $native=@(Invoke-Adb @('shell','cat',"/data/data/$package/files/probe-result.txt") -AllowNonzero)
                if ($native -match '^\s*[0-9]+\s*$') { $complete=$true; break }
                if ($attempt % 5 -eq 0) {
                    $pending=@(Invoke-Adb @('logcat','-d','-v','brief'))
                    $current=@(Get-AndroidApi21CaseLog -RawLog $pending -Marker $marker)
                    if ($current -match 'Fatal signal|FATAL EXCEPTION|VM aborting|terminated by signal|exiting due to signal|\*\*\*\s+\*\*\*\s+\*\*\*') { break }
                }
            }
        }
        Start-Sleep -Seconds 2
        $raw=@(Invoke-Adb @('logcat','-d','-v','brief'))
        $raw | Set-Content "$case/logcat-raw.log"
        $log=@(Get-AndroidApi21CaseLog -RawLog $raw -Marker $marker)
        $log | Set-Content "$case/logcat.log"
        Invoke-Adb @('pull',"/data/data/$package/files","$case/files") | Set-Content "$case/pull.log"
        $expected=if ($profile -eq 'bootstrap') { '42' } else { '0' }
        $received=($native -join '').Trim()
        if (!$complete -or $received -ne $expected) { throw "$profile native result '$received', expected '$expected'; see captured case files" }
        if ($log -match 'Fatal signal|FATAL EXCEPTION|VM aborting|terminated by signal|exiting due to signal|\*\*\*\s+\*\*\*\s+\*\*\*') { throw "$profile crashed; see scoped log" }
        if ($profile -eq 'strict') {
            & python "$repo/scripts/tests/require-modern-cpp.py" "$case/files/strict-cxx23.log"
            if ($LASTEXITCODE) { throw 'C++23 must pass all25 without SKIP' }
        }
        if ($profile -eq 'core' -and !($log -match 'QtCore 4\.8\.7 PASS')) { throw 'Missing QtCore behavior result' }
        $passed=1
        $skipped=0
        $summary=@()
        if ($profile -eq 'strict') { $passed=25 }
        if ($labels.ContainsKey($profile)) {
            $stdout=Get-Content "$case/files/suite.log"
            $summary=@($stdout | Where-Object { $_ -match '^---- [^:]+: [0-9]+ passed, [0-9]+ failed, [0-9]+ skipped ----\s*$' })
            $pattern='^---- '+[regex]::Escape($labels[$profile])+': ([1-9][0-9]*) passed, 0 failed, ([0-9]+) skipped ----\s*$'
            if ($summary.Count -ne 1 -or $summary[0] -notmatch $pattern) { throw "$profile has no successful ordinary report" }
            $passed=[int]$Matches[1]
            $skipped=[int]$Matches[2]
        }
        if ($labels.ContainsKey($profile)) {
            & python "$repo/scripts/run/android-baselines.py" --qt 4 --api $api --abi $Abi --case $profile --report "$case/files/suite.log"
            if ($LASTEXITCODE) { throw "Coverage regression: $profile" }
        }
        if ($profile -eq 'quick') {
            $stdout=Get-Content "$case/files/quick-smoke.txt"
            foreach ($check in $quickChecks) { if ($check -notin $stdout.Trim()) { throw "Missing gallery check: $check" } }
            foreach ($png in @('qml-gallery.png','widgets-gallery.png')) { if (!(Test-Path "$case/files/$png")) { throw "Missing rendered gallery frame: $png" } }
            $passed=$quickChecks.Count
        }
        Get-AndroidVerifiedHash $apk $installedApkSha | Out-Null
        Assert-Qt4RunGeneration
        if ($api -eq 21) {
            Get-AndroidVerifiedHash "$run/emulator-identity.json" $emulatorIdentitySha | Out-Null
            Get-AndroidVerifiedHash "$run/emulator-media.json" $emulatorMediaSha | Out-Null
        }
        Assert-AndroidGuestCpuBinding $run $guestCpu
        # Capture after forced release before the next profile clears logcat.
        Invoke-Adb @('shell','am','force-stop',$package) | Out-Null
        $removed=Invoke-Adb @('uninstall',$package)
        if (!($removed -match '^\s*Success\s*$')) { throw 'Cannot release tested APK' }
        $cleanupRaw=@(Invoke-Adb @('logcat','-d','-v','brief'))
        [IO.File]::WriteAllLines("$case/logcat-after-cleanup-raw.log",[string[]]$cleanupRaw,[Text.UTF8Encoding]::new($false))
        $cleanupScoped=@(Get-AndroidApi21CaseLog -RawLog $cleanupRaw -Marker $marker)
        [IO.File]::WriteAllLines("$case/logcat-after-cleanup.log",[string[]]$cleanupScoped,[Text.UTF8Encoding]::new($false))
        $cleanupJson=@(& python "$PSScriptRoot/android-final-log.py" case-cleanup --root $root --case $case --marker $marker --artifact-lease-held)
        if ($LASTEXITCODE) { throw 'Incomplete Qt4 case cleanup log evidence' }
        $caseCleanup=($cleanupJson -join [Environment]::NewLine) | ConvertFrom-Json
        Get-AndroidVerifiedHash $apk $installedApkSha | Out-Null
        Assert-Qt4RunGeneration
        $outcomes.Add([pscustomobject]@{case_cleanup_raw_logcat_sha256=$caseCleanup.case_cleanup_raw_logcat_sha256;case_cleanup_logcat_sha256=$caseCleanup.case_cleanup_logcat_sha256;host_process_owner_sha256=$emulatorOwner.OwnerSha;host_process_request_sha256=$emulatorOwner.RequestSha;guest_cpuinfo_sha256=$guestCpu.guest_cpuinfo_sha256;guest_cpu_baseline_sha256=$guestCpu.guest_cpu_baseline_sha256;emulator_identity_sha256=$emulatorIdentitySha;emulator_media_sha256=$emulatorMediaSha;profile=$profile;native_return=$(if ($profile -ne 'quick') { [int]$expected } else { $null });
            instrumentation_code=$(if ($profile -eq 'quick') { -1 } else { $null });log_marker=$marker;
            passed=$passed;failed=0;skipped=$skipped;summary=$summary;sdk_image_id=$sdkId;
            apk_sha256=$installedApkSha;apk_manifest_sha256=$apkManifestSha;
            apk_generation_manifest_sha256=$apkGenerationSha;examples_manifest_sha256=$examplesManifestSha})
        $outcomes | ConvertTo-Json -Depth 5 | Set-Content "$run/results.json"
        $completion=if ($profile -eq 'quick') { 'instrumentation code -1' } else { "native return $expected" }
        Write-Output "$profile PASS: $passed passed, 0 failed, $skipped skipped; $completion"
    }
} finally {
    try {
        $hostTree=& "$PSScriptRoot/android-api21-cleanup.ps1" -Adb $adb -Serial $serial -RunDirectory $run -EmulatorPid $emulatorOwner.Owner.frontend_pid -RequireFinalLog
    } finally {
        if ($emulatorOwner.Process -and !$hostTree) { $hostTree=Stop-AndroidOwnedProcess $emulatorOwner }
    }
}

# Selected profiles have no final collector, so retain the same post-cleanup
# input boundary as full runs, including APKs outside the selection.
Assert-Qt4RunGeneration
foreach ($outcome in $outcomes) {
    Get-AndroidVerifiedHash (Join-Path $root ($outcome.profile+'.apk')) $outcome.apk_sha256 | Out-Null
}
Assert-AndroidGuestCpuBinding $run $guestCpu
& python "$repo/scripts/build/qt4-android/artifact-manifest.py" check-apks --root $root --abi $Abi --artifact-lease-held
if ($LASTEXITCODE) { throw 'Qt4 APK/native generation changed during the suite' }
if ($api -eq 21) {
    Get-AndroidVerifiedHash "$run/emulator-identity.json" $emulatorIdentitySha | Out-Null
    Get-AndroidVerifiedHash "$run/emulator-media.json" $emulatorMediaSha | Out-Null
    & python "$PSScriptRoot/android-api21-identity.py" verify --root $root --run $run --abi $Abi
    if ($LASTEXITCODE) { throw 'API21 emulator/media changed during the Qt4 suite' }
}
$finalCaptureJson=@(& python "$PSScriptRoot/android-final-log.py" capture --root $root --directory $run --serial $serial --case (Join-Path $run $outcomes[-1].profile) --artifact-lease-held)
if ($LASTEXITCODE) { throw 'Incomplete Qt4 final log capture evidence' }
$finalCapture=($finalCaptureJson -join [Environment]::NewLine) | ConvertFrom-Json
foreach ($outcome in $outcomes) {
    foreach ($field in $finalCapture.PSObject.Properties) { $outcome | Add-Member -NotePropertyName $field.Name -NotePropertyValue $field.Value -Force }
    if ($outcome.host_process_owner_sha256 -cne $hostTree.host_process_owner_sha256 -or
            $outcome.host_process_request_sha256 -cne $hostTree.host_process_request_sha256) { throw 'Owned process tree changed after its cases' }
    foreach ($field in $hostTree.PSObject.Properties) { $outcome | Add-Member -NotePropertyName $field.Name -NotePropertyValue $field.Value -Force }
}
Write-AndroidOwnedProcessJson "$run/results.json" $outcomes
if ($fullRun) {
    & python "$repo/scripts/build/qt4-android/collect-api21-results.py" --root $root --run $RunName --abi $Abi --artifact-lease-held
    if ($LASTEXITCODE) { throw 'Incomplete Qt4 Android suite evidence' }
}

} finally { if ($artifactLock) { $artifactLock.Dispose() } }
