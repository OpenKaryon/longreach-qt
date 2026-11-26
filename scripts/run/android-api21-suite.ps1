# SPDX-License-Identifier: GPL-3.0-or-later
param([ValidateSet(5,6)][int]$QtMajor = 6, [ValidateSet('armeabi-v7a','arm64-v8a','x86','x86_64')][string]$Abi = 'armeabi-v7a', [string]$RunName='sdk-suite', [ValidateSet('on','mesa')][string]$Gpu='on',
      [string[]]$CaseNames, [switch]$SoundCacheTeardown, [switch]$SpeechBehavior, [switch]$AndroidExtrasBehavior, [switch]$Api10Compatibility, [switch]$DebugQtPlugins, [ValidateSet('default','software')][string]$QtQuickBackend='default',
      [string]$AndroidSdk=$env:ANDROID_HOME, [string]$OutputDirectory, [ValidateSet('default','x86')][string]$ActivityManagerAbi='default')
$ErrorActionPreference='Stop'
if ($ActivityManagerAbi -eq 'x86' -and $Abi -ne 'x86_64') { throw 'The x86 Activity Manager helper requires an x86_64 guest' }
if ($AndroidExtrasBehavior) {
    if ($QtMajor -ne 5 -or $SoundCacheTeardown -or $SpeechBehavior -or $Api10Compatibility -or $PSBoundParameters.ContainsKey('CaseNames')) {
        throw 'AndroidExtras requires an exclusive QtMajor5 diagnostic without CaseNames'
    }
    if (!$PSBoundParameters.ContainsKey('RunName')) { $RunName='android-extras-'+[guid]::NewGuid().ToString('N') }
    if ($RunName -cnotmatch '^[a-z0-9][a-z0-9-]{0,63}$') { throw 'Invalid AndroidExtras diagnostic run name' }
}
if ($SpeechBehavior) {
    if ($QtMajor -ne 5) { throw 'TTS behavior requires QtMajor 5' }
    if ($SoundCacheTeardown -or $Api10Compatibility -or $PSBoundParameters.ContainsKey('CaseNames')) {
        throw 'TTS behavior cannot be combined with another diagnostic or CaseNames'
    }
    if (!$PSBoundParameters.ContainsKey('RunName')) { $RunName='tts-behavior-'+[guid]::NewGuid().ToString('N') }
    if ($RunName -cnotmatch '^[a-z0-9][a-z0-9-]{0,63}$') { throw 'Invalid TTS diagnostic run name' }
}
if ($Api10Compatibility) {
    if ($QtMajor -ne 5 -or $Abi -notin @('armeabi-v7a','x86')) { throw 'API10 compatibility requires QtMajor 5 and ARMv7/x86' }
    if ($SoundCacheTeardown -or $PSBoundParameters.ContainsKey('CaseNames')) { throw 'API10 compatibility cannot be combined with SoundCacheTeardown or CaseNames' }
    if (!$PSBoundParameters.ContainsKey('RunName')) { $RunName='api10-on-api21-'+[guid]::NewGuid().ToString('N') }
    if ($RunName -cnotmatch '^[a-z0-9][a-z0-9-]{0,63}$') { throw 'Invalid API10 compatibility run name' }
}
if ($SoundCacheTeardown) {
    if ($QtMajor -ne 5 -or $PSBoundParameters.ContainsKey('CaseNames')) {
        throw 'Sound-cache teardown requires QtMajor 5 and cannot be combined with CaseNames'
    }
    if (!$PSBoundParameters.ContainsKey('RunName')) { $RunName='sound-cache-'+[guid]::NewGuid().ToString('N') }
    if ($RunName -cnotmatch '^[a-z0-9][a-z0-9-]{0,63}$') { throw 'Invalid sound diagnostic run name' }
}
. "$PSScriptRoot/android/android-emulator-state.ps1"
$Gpu=$Gpu.ToLowerInvariant()
$QtQuickBackend=$QtQuickBackend.ToLowerInvariant()
. "$PSScriptRoot/android/android-api21-log.ps1"
. "$PSScriptRoot/android/android-api21-adb.ps1"
. "$PSScriptRoot/android/android-wait-boot.ps1"
. "$PSScriptRoot/android/android-cpu.ps1"
. "$PSScriptRoot/android/android-owned-process.ps1"
. "$PSScriptRoot/android/android-process-exit.ps1"
if ($AndroidExtrasBehavior) { . "$PSScriptRoot/android/android-extras.ps1" }
. "$PSScriptRoot/android/android-shell.ps1"
. "$PSScriptRoot/android/android-shell-status.ps1"
$repo=(Resolve-Path "$PSScriptRoot/../..").Path
if (!$AndroidSdk) { throw 'Set ANDROID_HOME or pass -AndroidSdk' }
$AndroidSdk=(Resolve-Path -LiteralPath $AndroidSdk).Path
$suffix = if ($Abi -eq 'armeabi-v7a') { '' } else { "-$Abi" }
if (!$OutputDirectory) {
    $OutputDirectory=if ($Api10Compatibility) { "$repo/artifacts/qt5-android-gingerbread$suffix" }
        else { "$repo/artifacts/qt$QtMajor-android-lollipop$suffix" }
}
$root=(Resolve-Path -LiteralPath $OutputDirectory).Path
if (($SoundCacheTeardown -or $SpeechBehavior -or $AndroidExtrasBehavior -or $Api10Compatibility) -and (Test-Path -LiteralPath (Join-Path $root $RunName))) {
    throw 'Diagnostic run already exists; preserve it and choose another name'
}
. "$repo/scripts/build/android-api21/artifact-lock.ps1"
$artifactLock=Enter-AndroidArtifactLock $root
try {
Clear-AndroidResultAggregates $root
$adb="$AndroidSdk/platform-tools/adb.exe"
& python "$repo/scripts/build/android-api21/artifact-manifest.py" check-apks --root $root --qt-major $QtMajor --abi $Abi --artifact-lease-held
if ($LASTEXITCODE) { throw 'Refusing incomplete or mismatched APK generation' }
$apkManifestSha=(Get-FileHash -LiteralPath "$root/apk-manifest.json" -Algorithm SHA256).Hash.ToLowerInvariant()
$apkManifest=Get-Content -LiteralPath "$root/apk-manifest.json" -Raw | ConvertFrom-Json
Get-AndroidVerifiedHash "$root/apk-manifest.json" $apkManifestSha | Out-Null
Assert-AndroidNoEmulatorRunning -Message 'Stop the existing Android emulator before preparing a fresh suite.'
$serial = 'emulator-5582'
function Invoke-Adb {
    param([string[]]$Parameters,[switch]$AllowNonzero)
    Invoke-AndroidApi21Adb -Adb $adb -Serial $serial -Parameters $Parameters -AllowNonzero:$AllowNonzero
}
function Get-ActivityManagerArguments([string[]]$Arguments) {
    if ($ActivityManagerAbi -eq 'x86' -and $Arguments[0] -eq 'am') {
        return @('CLASSPATH=/system/framework/am.jar','/system/bin/app_process32','/system/bin','com.android.commands.am.Am') + @($Arguments | Select-Object -Skip 1)
    }
    return $Arguments
}
function Invoke-CheckedAndroidShell {
    param([string]$Step,[string[]]$Arguments,[string]$OutputPath)
    $budget=if ($Arguments[0] -eq 'am') { 30000 } else { 15000 }
    $command=((Get-ActivityManagerArguments $Arguments) | ForEach-Object { ConvertTo-AndroidShellArgument $_ }) -join ' '
    Invoke-AndroidSetupCommand -Adb $adb -Serial $serial -Step $Step -Command $command -OutputPath $OutputPath -TimeoutMilliseconds $budget | Out-Null
}
$apps = @(Get-Content -LiteralPath "$repo/tests/expected-apps.txt" | Where-Object { $_ -match '^[a-z]' -and $_ -ne 'smoke-runner' })
if ($apps.Count -ne 8) { throw 'Expected exactly eight shared applications' }
# Reject an invalid selection before fetching media or starting a guest.
$cases = @(@{ App='qt-selftest'; Name='strict-cxx23'; Arguments='--modern-cpp'; Strict=$true })
$cases += @($apps | ForEach-Object { @{ App=$_; Name=$_; Arguments='--selftest'; Strict=$false } })
if ($QtMajor -eq 5) {
    $cases += @{ App='qt-selftest'; Name='strict-cxx23-extended'; Arguments='--modern-cpp'; Strict=$true; Extended=$true }
    $cases += @{ App='qt-selftest'; Name='qt-selftest-extended'; Arguments='--selftest'; Strict=$false; Extended=$true }
}
$cases += @{ App='widgets-gallery'; Name='widgets-gui'; Arguments='--gallery-selftest'; Strict=$false }
$cases += @{ App='quick-qml-gallery'; Name='qml-gui'; Arguments='--gallery-selftest'; Strict=$false }
if ($SoundCacheTeardown) {
    $cases=@(@{App='qt-selftest';Name='sound-cache-teardown';Arguments='--sound-cache-teardown';Strict=$false;Extended=$true})
} elseif ($SpeechBehavior) {
    $cases=@(@{App='multimedia-lab';Name='tts-behavior';Arguments='--tts-behavior';Strict=$false})
} elseif ($AndroidExtrasBehavior) {
    $cases=@(@{App='qt-selftest';Name='android-extras';Arguments='--android-extras';Strict=$false})
} elseif ($Api10Compatibility) {
    $cases=@(@{App='qt-selftest';Name='api10-selftest';Arguments='--selftest';Strict=$false})
} elseif ($CaseNames) {
    foreach ($name in $CaseNames) {
        if ($name -notin $cases.Name) { throw "Unknown suite case: $name" }
    }
    $cases = @($cases | Where-Object { $_.Name -in $CaseNames })
}
if ($Api10Compatibility) {
    $forwardCoverage=@{source_api=10;guest_api=21;coverage_api=10;coverage_case='qt-selftest';
        coverage_policy_sha256=(Get-FileHash -LiteralPath "$repo/scripts/run/android/android-baselines.json" -Algorithm SHA256).Hash.ToLowerInvariant()}
}
foreach ($app in $apps) {
    if (!(Test-Path -LiteralPath "$root/apk/$app.apk")) { throw "Missing APK: $app" }
}
if ($QtMajor -eq 5 -and !(Test-Path -LiteralPath "$root/apk/extended/qt-selftest.apk")) { throw 'Missing extended Qt5 selftest APK' }
& "$repo/scripts/fetch/qt6-android.ps1" -AndroidSdk $AndroidSdk -Scope test -Abi $Abi
& python "$repo/scripts/build/qt6-android/prepare-emulator.py" --repo $repo --output $root --abi $Abi
if ($LASTEXITCODE) { throw 'Could not prepare API21 emulator inputs' }
$emulatorName = switch ($Abi) {
    'x86' { 'emulator-32.1.11/emulator/emulator.exe' }
    'x86_64' { 'emulator-32.1.11/emulator/emulator.exe' }
    'arm64-v8a' { 'emulator-25.2.5/tools/emulator.exe' }
    default { 'tools/emulator-arm.exe' }
}
$emulator="$root/media/$emulatorName"
$emulatorOwner=& "$PSScriptRoot/qt6-android-start.ps1" -OutputDirectory $root -Emulator $emulator -RunName $RunName -Gpu $Gpu -Abi $Abi -PassThru
$run = "$root/$RunName"
$outcomes = [Collections.Generic.List[object]]::new()
$caseError=$null
try {
    $emulatorLaunch=Get-Content -LiteralPath "$run/emulator-launch.json" -Raw | ConvertFrom-Json
    $emulatorIdentitySha=(Get-FileHash -LiteralPath "$run/emulator-identity.json").Hash.ToLowerInvariant()
    $emulatorMediaSha=(Get-FileHash -LiteralPath "$run/emulator-media.json").Hash.ToLowerInvariant()
    $emulatorLaunchSha=(Get-FileHash -LiteralPath "$run/emulator-launch.json" -Algorithm SHA256).Hash.ToLowerInvariant()
    $runOptions=@{schema_version=1;qt_major=$QtMajor;abi=$Abi;gpu_requested=$Gpu;
      debug_qt_plugins=[bool]$DebugQtPlugins;qt_quick_backend=$QtQuickBackend}
    if ($SoundCacheTeardown) { $runOptions.diagnostic='qt5-sound-cache-teardown' }
    if ($SpeechBehavior) { $runOptions.diagnostic='qt5-tts-behavior' }
    if ($AndroidExtrasBehavior) { $runOptions.diagnostic='qt5-android-extras' }
    if ($Api10Compatibility) { $runOptions.diagnostic='qt5-api10-on-api21'; $runOptions += $forwardCoverage }
    Invoke-AndroidApi21Adb -Adb $adb -Parameters @('start-server') | Out-Null
    # Do not reset offline transports belonging to other ADB clients.
    Wait-AndroidBoot -Adb $adb -Serial $serial -RunDirectory $run -EmulatorPid $emulatorOwner.Process.Id -EmulatorProcess $emulatorOwner.Process
    $expected = @{ 'ro.build.version.release'='5.0.2'; 'ro.build.version.sdk'='21'; 'ro.product.cpu.abi'=$Abi }
    foreach ($property in $expected.Keys) {
        $value = ((Invoke-Adb @('shell','getprop',$property)) -join '').Trim()
        if ($value -ne $expected[$property]) { throw "Unexpected $property=$value" }
    }
    Invoke-Adb @('shell','getprop') | Set-Content -LiteralPath "$run/guest-properties.txt"
    if ($ActivityManagerAbi -eq 'x86') {
        Invoke-Adb @('pull','/system/bin/app_process32',"$run/activity-manager-helper.elf") | Set-Content "$run/activity-manager-helper-pull.log"
        $helper=[IO.File]::ReadAllBytes("$run/activity-manager-helper.elf")
        if ($helper.Length -lt 52 -or [BitConverter]::ToString($helper[0..6]) -cne '7F-45-4C-46-01-01-01' -or
                $helper[18] -ne 3 -or $helper[19] -ne 0) { throw 'Activity Manager helper is not an ELF32 x86 executable' }
        $runOptions.activity_manager_abi='x86'
        $runOptions.activity_manager_helper_sha256=(Get-FileHash "$run/activity-manager-helper.elf").Hash.ToLowerInvariant()
    }
    $runOptions | ConvertTo-Json | Set-Content -LiteralPath "$run/run-options.json" -Encoding utf8
    $runOptionsSha=(Get-FileHash -LiteralPath "$run/run-options.json" -Algorithm SHA256).Hash.ToLowerInvariant()
    Invoke-Adb @('shell','cat','/proc/cpuinfo') | Set-Content -LiteralPath "$run/guest-cpuinfo.txt"
    $guestCpu=Save-AndroidGuestCpuBaseline $run $Abi
    Invoke-CheckedAndroidShell -Step unlock -Arguments @('input','keyevent','82') -OutputPath "$run/setup-unlock.stdout"
    foreach ($case in $cases) {
        $app = $case.App
        $package = if ($QtMajor -eq 6) { 'org.longreachqt.examples.qt6.' + $app.Replace('-','_') } else { 'org.longreachqt.examples.' + $app.Replace('-','') }
        $destination = "$run/$($case.Name)"
        New-Item -ItemType Directory -Path $destination | Out-Null
        $apkRelative = if ($case.Extended) { "apk/extended/$app.apk" } else { "apk/$app.apk" }
        $apk = "$root/$apkRelative"
        Get-AndroidVerifiedHash "$root/apk-manifest.json" $apkManifestSha | Out-Null
        $installedApkSha=Get-AndroidVerifiedHash $apk ($apkManifest.files.PSObject.Properties[$apkRelative].Value)
        $install = Invoke-Adb @('install','-r',$apk)
        $install | Set-Content -LiteralPath "$destination/install.txt"
        if (!($install -match '^\s*Success\s*$')) { throw "APK install failed: $app" }
        Get-AndroidVerifiedHash $apk $installedApkSha | Out-Null
        Get-AndroidVerifiedHash "$root/apk-manifest.json" $apkManifestSha | Out-Null
        Invoke-CheckedAndroidShell -Step force-stop-before -Arguments @('am','force-stop',$package) -OutputPath "$destination/force-stop-before.stdout"
        $clear = Invoke-Adb @('shell','pm','clear',$package)
        if (!($clear -match '^\s*Success\s*$')) { throw "Could not reset previous app reports: $package" }
        # API21's default clear leaves system-buffer deaths from the prior APK.
        Invoke-Adb @('logcat','-b','all','-c') | Out-Null
        $logMarker = 'BEGIN-' + [guid]::NewGuid().ToString('N')
        $logMarker | Set-Content "$destination/log-marker.txt"
        Invoke-CheckedAndroidShell -Step launch-marker -Arguments @('log','-p','i','-t','LongreachCase',$logMarker) -OutputPath "$destination/launch-marker.stdout"
        $launchArguments = @('shell') + @(Get-ActivityManagerArguments @('am','start','-n',"$package/org.longreachqt.examples.SmokeActivity",'--es','applicationArguments',$case.Arguments))
        if ($DebugQtPlugins) { $launchArguments += @('--ez','debugQtPlugins','true') }
        if ($QtQuickBackend -ne 'default') {
            $launchArguments += @('--es','qtQuickBackend',$QtQuickBackend)
        }
        Get-AndroidVerifiedHash $apk $installedApkSha | Out-Null
        Get-AndroidVerifiedHash "$root/apk-manifest.json" $apkManifestSha | Out-Null
        Invoke-Adb $launchArguments | Set-Content -LiteralPath "$destination/launch.txt"
        $complete = $false
        $applicationPid = $null
        $nativeResult = @()
        for ($attempt = 0; $attempt -lt 300; $attempt++) {
            Start-Sleep -Seconds 2
            if ($AndroidExtrasBehavior) { Observe-AndroidExtrasServices -Adb $adb -Serial $serial -Directory $destination -Package $package -Marker $logMarker }
            $nativeResult = @(Invoke-Adb @('shell','cat',"/data/data/$package/files/selftest-result.txt") -AllowNonzero)
            if ($nativeResult -match '^\s*[0-9]+\s*$') { $complete = $true; break }
            if ($attempt % 5 -eq 0) {
                $pendingRaw = @(Invoke-Adb @('logcat','-d','-v','brief'))
                $pendingLog = @(Get-AndroidApi21CaseLog -RawLog $pendingRaw -Marker $logMarker)
                $lifecycle=Get-AndroidApplicationLifecycle $pendingLog $package
                if ($lifecycle) {
                    $applicationPid=$lifecycle.process_id
                    $applicationPid | Set-Content "$destination/process-id.txt"
                    if ($lifecycle.death_line) {
                        # Completion can appear after the previous cat but
                        # before this death observation. Re-read once without
                        # replacing either the zero-result or natural-exit gate.
                        $nativeResult = @(Invoke-AndroidExitQuery -Adb $adb -Serial $serial -Command @('shell','cat',"/data/data/$package/files/selftest-result.txt") -Directory $destination -Name 'native-result-after-death' -TimeoutMilliseconds 5000 -AllowNonzero)
                        $complete = [bool]($nativeResult -match '^\s*[0-9]+\s*$')
                        break
                    }
                }
            }
        }
        if (!$complete -or !($nativeResult -match '^\s*0\s*$')) {
            # Copy failure reports before owned cleanup powers down the guest.
            # A failed pull must preserve the original native-result failure.
            try {
                Invoke-AndroidApi21Adb -Adb $adb -Serial $serial -Parameters @('pull',"/data/data/$package/files","$destination/files") `
                    -AllowNonzero -TimeoutMilliseconds 15000 | Set-Content -LiteralPath "$destination/failure-pull.log"
            } catch {
                $_ | Out-String | Set-Content -LiteralPath "$destination/failure-pull.log"
            }
            throw "$($case.Name) did not complete with zero: $nativeResult"
        }
        try {
            $exitProof=Wait-AndroidApplicationExit -Adb $adb -Serial $serial -Directory $destination -Package $package -Marker $logMarker
        } catch {
            $exitError=$_
            # Native zero precedes Qt/JNI teardown. Keep the reports when the
            # process-exit gate fails, before owned cleanup powers down the guest.
            try {
                Invoke-AndroidApi21Adb -Adb $adb -Serial $serial -Parameters @('pull',"/data/data/$package/files","$destination/files") `
                    -AllowNonzero -TimeoutMilliseconds 15000 | Set-Content -LiteralPath "$destination/failure-pull.log"
            } catch {
                $_ | Out-String | Set-Content -LiteralPath "$destination/failure-pull.log"
            }
            throw $exitError
        }
        $log=@(Get-Content -LiteralPath "$destination/logcat.log")
        Invoke-Adb @('pull',"/data/data/$package/files","$destination/files") | Set-Content -LiteralPath "$destination/pull.log"
        if ($log -match 'FATAL EXCEPTION|Fatal signal|exiting due to signal|terminated by signal|VM aborting') { throw "$($case.Name) crashed; see logcat.log" }
        $stdout = "$destination/files/selftest.stdout"
        if (!(Test-Path -LiteralPath $stdout)) { throw "$($case.Name) returned zero without its report" }
        $stdoutSha=(Get-FileHash -LiteralPath $stdout -Algorithm SHA256).Hash.ToLowerInvariant()
        $report = Get-Content -LiteralPath $stdout
        if ($SoundCacheTeardown) {
            $soundStdoutHash=$stdoutSha
            & python "$repo/scripts/tests/android/require-android-sound-cache.py" $stdout
            if ($LASTEXITCODE) { throw 'Sound-cache pre-exit protocol failed' }
            Get-AndroidVerifiedHash $stdout $soundStdoutHash | Out-Null
        } elseif ($SpeechBehavior) {
            & python "$repo/scripts/tests/android/require-android-tts.py" $stdout
            if ($LASTEXITCODE) { throw 'TTS behavior observations failed' }
            Get-AndroidVerifiedHash $stdout $stdoutSha | Out-Null
        } elseif ($AndroidExtrasBehavior) {
            & python "$repo/scripts/tests/android/require-android-extras.py" $stdout
            if ($LASTEXITCODE) { throw 'AndroidExtras observations failed' }
            Get-AndroidVerifiedHash $stdout $stdoutSha | Out-Null
        } elseif ($case.Strict) {
            & python "$repo/scripts/tests/require-modern-cpp.py" $stdout
            if ($LASTEXITCODE -ne 0) { throw 'C++23 must pass exactly25 checks without SKIP' }
        } elseif (!($report -match '^---- [^:]+: [1-9][0-9]* passed, 0 failed, [0-9]+ skipped ----\s*$')) {
            throw "$($case.Name) has no successful ordinary summary"
        }
        if (!$SoundCacheTeardown -and !$SpeechBehavior -and !$AndroidExtrasBehavior) {
            $coverageApi=21; $coverageCase=$case.Name
            if ($Api10Compatibility) {
                $coverageApi=10; $coverageCase='qt-selftest'
                Get-AndroidVerifiedHash "$repo/scripts/run/android/android-baselines.json" $forwardCoverage.coverage_policy_sha256 | Out-Null
            }
            & python "$repo/scripts/run/android/android-baselines.py" --qt $QtMajor --api $coverageApi --abi $Abi --case $coverageCase --report $stdout
            if ($LASTEXITCODE) { throw "Coverage regression: $($case.Name)" }
            if ($Api10Compatibility) { Get-AndroidVerifiedHash "$repo/scripts/run/android/android-baselines.json" $forwardCoverage.coverage_policy_sha256 | Out-Null }
        }
        $summary = @($report | Where-Object { $_ -match 'passed,.*failed,.*skipped' })
        if ($SpeechBehavior -or $AndroidExtrasBehavior) { $summary=@() }
        Get-AndroidVerifiedHash $apk $installedApkSha | Out-Null
        Get-AndroidVerifiedHash "$root/apk-manifest.json" $apkManifestSha | Out-Null
        Get-AndroidVerifiedHash "$run/run-options.json" $runOptionsSha | Out-Null
        Get-AndroidVerifiedHash "$run/emulator-launch.json" $emulatorLaunchSha | Out-Null
        Get-AndroidVerifiedHash "$run/emulator-identity.json" $emulatorIdentitySha | Out-Null
        Get-AndroidVerifiedHash "$run/emulator-media.json" $emulatorMediaSha | Out-Null
        Assert-AndroidGuestCpuBinding $run $guestCpu
        Invoke-CheckedAndroidShell -Step force-stop-after -Arguments @('am','force-stop',$package) -OutputPath "$destination/force-stop-after.stdout"
        # This is a disposable task-owned guest. Release extracted native
        # libraries between cases; all reports and exact APKs remain on host.
        $removed = Invoke-Adb @('uninstall',$package)
        if (!($removed -match '^\s*Success\s*$')) { throw "Could not release tested APK: $package" }
        # Observe teardown after release, before the next case clears logcat.
        $cleanupRaw=@(Invoke-AndroidExitQuery -Adb $adb -Serial $serial -Command @('logcat','-d','-v','brief') -Directory $destination -Name 'case-cleanup-logcat' -TimeoutMilliseconds 5000)
        $cleanupRaw | Set-Content -LiteralPath "$destination/logcat-after-cleanup-raw.log"
        $cleanupLog=@(Get-AndroidApi21CaseLog -RawLog $cleanupRaw -Marker $logMarker)
        $cleanupLog | Set-Content -LiteralPath "$destination/logcat-after-cleanup.log"
        $cleanupState=Get-AndroidApplicationLifecycle $cleanupLog $package
        if (!$cleanupState -or !$cleanupState.death_line -or $cleanupState.process_id -ne $exitProof.process_id -or
                $cleanupState.start_line -cne $exitProof.start_line -or $cleanupState.death_line -cne $exitProof.death_line) {
            throw 'API21 case cleanup lost its application process exit'
        }
        Get-AndroidVerifiedHash $stdout $stdoutSha | Out-Null
        $outcomes.Add([pscustomobject]@{ host_process_owner_sha256=$emulatorOwner.OwnerSha;host_process_request_sha256=$emulatorOwner.RequestSha;guest_cpuinfo_sha256=$guestCpu.guest_cpuinfo_sha256; guest_cpu_baseline_sha256=$guestCpu.guest_cpu_baseline_sha256; emulator_identity_sha256=$emulatorIdentitySha; emulator_media_sha256=$emulatorMediaSha; name=$case.Name; log_marker=$logMarker; app=$app; arguments=$case.Arguments; apk_relative=$apkRelative; result=0; stdout_sha256=$stdoutSha; summary=$summary; process_id=$exitProof.process_id; process_exit_confirmed=$true; process_exit_proof_sha256=(Get-FileHash "$destination/process-exit.json").Hash.ToLowerInvariant(); launch_arguments=@($launchArguments); gpu=$emulatorLaunch.gpu_effective; run_options_sha256=$runOptionsSha; emulator_launch_sha256=$emulatorLaunchSha; apk_sha256=$installedApkSha; apk_manifest_sha256=$apkManifestSha; finished_utc=[DateTime]::UtcNow.ToString('o') })
        $outcomes[-1] | Add-Member -NotePropertyMembers @{
            case_cleanup_raw_logcat_sha256=(Get-FileHash "$destination/logcat-after-cleanup-raw.log" -Algorithm SHA256).Hash.ToLowerInvariant();
            case_cleanup_logcat_sha256=(Get-FileHash "$destination/logcat-after-cleanup.log" -Algorithm SHA256).Hash.ToLowerInvariant()}
        if ($SoundCacheTeardown -or $SpeechBehavior -or $AndroidExtrasBehavior -or $Api10Compatibility) {
            $diagnostic=if ($SoundCacheTeardown) { 'qt5-sound-cache-teardown' } elseif ($SpeechBehavior) { 'qt5-tts-behavior' } elseif ($AndroidExtrasBehavior) { 'qt5-android-extras' } else { 'qt5-api10-on-api21' }
            $outcomes[-1] | Add-Member -NotePropertyMembers @{scope='single-case';qualification=$false;
                diagnostic=$diagnostic;diagnostic_stdout_sha256=$stdoutSha}
            if ($Api10Compatibility) { $outcomes[-1] | Add-Member -NotePropertyMembers $forwardCoverage }
            if ($AndroidExtrasBehavior) { $outcomes[-1] | Add-Member -NotePropertyMembers @{extras_services_sha256=(Get-FileHash -LiteralPath "$destination/extras-services.json").Hash.ToLowerInvariant()} }
        }
        $outcomes | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "$run/results.json"
        Write-Output "$($case.Name): $($summary -join ' ')"
    }
} catch {
    $caseError=$_
    throw
} finally {
    try {
        $hostTree=& "$PSScriptRoot/android/android-api21-cleanup.ps1" -Adb $adb -Serial $serial -RunDirectory $run -EmulatorPid $emulatorOwner.Owner.frontend_pid -RequireFinalLog
    } catch {
        if ($caseError) {
            $errors=[Exception[]]@($caseError.Exception,$_.Exception)
            throw [AggregateException]::new('Android case failed and cleanup also failed',$errors)
        }
        throw
    }
}

# A filtered run has no final collector, so verify the tested inputs here too.
# Cleanup is an external boundary and must precede these final checks.
Get-AndroidVerifiedHash "$run/run-options.json" $runOptionsSha | Out-Null
Get-AndroidVerifiedHash "$run/emulator-launch.json" $emulatorLaunchSha | Out-Null
Get-AndroidVerifiedHash "$run/emulator-identity.json" $emulatorIdentitySha | Out-Null
Get-AndroidVerifiedHash "$run/emulator-media.json" $emulatorMediaSha | Out-Null
Assert-AndroidGuestCpuBinding $run $guestCpu
Get-AndroidVerifiedHash "$root/apk-manifest.json" $apkManifestSha | Out-Null
foreach ($outcome in $outcomes) {
    Get-AndroidVerifiedHash (Join-Path $root $outcome.apk_relative) $outcome.apk_sha256 | Out-Null
}
& python "$repo/scripts/build/android-api21/artifact-manifest.py" check-apks --root $root --qt-major $QtMajor --abi $Abi --artifact-lease-held
if ($LASTEXITCODE) { throw 'APK generation changed during the API21 suite' }

& python "$PSScriptRoot/android/android-api21-identity.py" verify --root $root --run $run --abi $Abi
if ($LASTEXITCODE) { throw 'API21 emulator/media changed during the suite' }
foreach ($outcome in $outcomes) {
    if ($outcome.host_process_owner_sha256 -cne $hostTree.host_process_owner_sha256 -or
            $outcome.host_process_request_sha256 -cne $hostTree.host_process_request_sha256) { throw 'Owned process tree changed after its cases' }
    foreach ($field in $hostTree.PSObject.Properties) { $outcome | Add-Member -NotePropertyName $field.Name -NotePropertyValue $field.Value -Force }
}
foreach ($outcome in $outcomes) {
    Get-AndroidVerifiedHash "$run/$($outcome.name)/files/selftest.stdout" $outcome.stdout_sha256 | Out-Null
    $outcome | Add-Member -NotePropertyMembers @{
        final_logcat_sha256=(Get-FileHash "$run/final-logcat.log" -Algorithm SHA256).Hash.ToLowerInvariant();
        final_logcat_capture_sha256=(Get-FileHash "$run/final-logcat-capture.json" -Algorithm SHA256).Hash.ToLowerInvariant()}
    if ($AndroidExtrasBehavior) {
        $extrasCase="$run/$($outcome.name)"
        Write-AndroidOwnedProcessJson "$extrasCase/extras-case-pending.json" $outcome
        & python "$PSScriptRoot/android/android-extras-state.py" validate --case $extrasCase --package 'org.longreachqt.examples.qtselftest' --receipt "$extrasCase/extras-case-pending.json" --final-run $run
        if ($LASTEXITCODE) { throw 'Post-cleanup Service evidence is incomplete' }
    }
    if ($SoundCacheTeardown -or $SpeechBehavior -or $AndroidExtrasBehavior -or $Api10Compatibility) { $outcome | Add-Member -NotePropertyName completed -NotePropertyValue $true }
}
if ($Api10Compatibility) { Get-AndroidVerifiedHash "$repo/scripts/run/android/android-baselines.json" $forwardCoverage.coverage_policy_sha256 | Out-Null }
Write-AndroidOwnedProcessJson "$run/results.json" $outcomes
& python "$PSScriptRoot/android/android-api21-exit.py" --root $root --run $RunName --qt-major $QtMajor --abi $Abi --artifact-lease-held
if ($LASTEXITCODE) { throw 'API21 post-cleanup termination evidence is incomplete' }
if ($SoundCacheTeardown) {
    & python "$PSScriptRoot/android/android-api21-sound-cache.py" --root $root --run $RunName --abi $Abi --artifact-lease-held
    if ($LASTEXITCODE) { throw 'API21 sound diagnostic evidence is incomplete' }
} elseif ($SpeechBehavior) {
    & python "$PSScriptRoot/android/android-api21-tts.py" --root $root --run $RunName --abi $Abi --artifact-lease-held
    if ($LASTEXITCODE) { throw 'API21 TTS diagnostic evidence is incomplete' }
} elseif ($AndroidExtrasBehavior) {
    & python "$PSScriptRoot/android/android-api21-extras.py" --root $root --run $RunName --abi $Abi --artifact-lease-held
    if ($LASTEXITCODE) { throw 'API21 AndroidExtras evidence is incomplete' }
} elseif ($Api10Compatibility) {
    & python "$PSScriptRoot/android/android-api21-forward.py" --root $root --run $RunName --abi $Abi --artifact-lease-held
    if ($LASTEXITCODE) { throw 'API21 forward diagnostic evidence is incomplete' }
} elseif (!$CaseNames) {
    & python "$repo/scripts/build/android-api21/collect-results.py" --root $root --run $RunName --abi $Abi --qt-major $QtMajor --artifact-lease-held
    if ($LASTEXITCODE) { throw 'Incomplete API21 suite evidence' }
}

} finally { if ($artifactLock) { $artifactLock.Dispose() } }
