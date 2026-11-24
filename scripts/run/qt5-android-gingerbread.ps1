# SPDX-License-Identifier: GPL-3.0-or-later
#Requires -Version 7.0

param(
    [ValidateSet('armeabi-v7a','x86')][string] $Abi = 'armeabi-v7a',
    [Parameter(Mandatory)] [string] $Apk,
    [Parameter(Mandatory)] [string] $SystemDirectory,
    [Parameter(Mandatory)] [string] $Emulator,
    [Parameter(Mandatory)] [string] $Kernel,
    [Parameter(Mandatory)] [string] $Ramdisk,
    [Parameter(Mandatory)] [string] $OutputDirectory,
    [string] $AndroidSdk = $env:ANDROID_HOME,
    [string] $Package = 'org.longreachqt.examples.probe',
    [string] $ApplicationArguments = '--selftest',
    [ValidateSet('16', '32')] [string] $RasterImageDepth = '32',
    [ValidateSet('default', 'software')] [string] $QtQuickBackend = 'software',
    [switch] $StrictCxx23,
    [switch] $RuntimeProbe,
    [string] $SdkImageId,
    [string] $CaseName,
    [string] $BatchReceipt,
    [string] $ArtifactRoot,
    [switch] $ClassicEmulator,
    [switch] $DebugQtPlugins,
    [switch] $NativeSensorFixture
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/android-emulator-state.ps1"
. "$PSScriptRoot/android-shell.ps1"
$Abi=$Abi.ToLowerInvariant()
$QtQuickBackend=$QtQuickBackend.ToLowerInvariant()
$crashHoldDiagnostic=$ApplicationArguments -match '(^|\s)--android-crash-hold(\s|$)'
if ($crashHoldDiagnostic -and ($StrictCxx23 -or $RuntimeProbe -or $CaseName -or $BatchReceipt)) {
    throw 'Post-main crash hold is a standalone diagnostic, not a qualification case'
}
$soundCacheTeardown=$ApplicationArguments -ceq '--sound-cache-teardown'
if ($ApplicationArguments -match '(^|\s)--sound-cache-teardown(\s|$)' -and !$soundCacheTeardown) {
    throw 'Sound-cache teardown requires exactly --sound-cache-teardown'
}
if ($soundCacheTeardown -and ($StrictCxx23 -or $RuntimeProbe -or $CaseName -or $BatchReceipt)) {
    throw 'Sound-cache teardown is a standalone diagnostic, not a strict/probe/batch qualification case'
}
if ($RuntimeProbe) {
    $StrictCxx23=$true
    if (!$PSBoundParameters.ContainsKey('Package')) { $Package='org.longreachqt.donut' }
}
if ($NativeSensorFixture -and ($Abi -ne 'x86' -or $StrictCxx23 -or $RuntimeProbe -or
        $ApplicationArguments -cne '--selftest' -or $Package -cne 'org.longreachqt.examples.qtselftest')) {
    throw 'Native sensor inputs require an ordinary x86 Qt5 selftest'
}
$completionName=if ($RuntimeProbe) { 'probe-result.txt' } else { 'selftest-result.txt' }
$stdoutName=if ($RuntimeProbe) { 'strict-cxx23.log' } else { 'selftest.stdout' }
$activity=if ($RuntimeProbe) { 'org.longreachqt.donut.ProbeActivity' } else { 'org.longreachqt.examples.SmokeActivity' }

. "$PSScriptRoot/android-wait-boot.ps1"
. "$PSScriptRoot/android-cpu.ps1"
. "$PSScriptRoot/android-owned-process.ps1"
. "$PSScriptRoot/android-process-exit.ps1"
$repo = (Resolve-Path "$PSScriptRoot/../..").Path
. "$PSScriptRoot/android-case-state.ps1"
. "$repo/scripts/build/android-api21/artifact-lock.ps1"
$apkInput=(Get-Item -LiteralPath $Apk).FullName
$roots=Get-AndroidApi10CaseRoots -Apk $apkInput -Directory $OutputDirectory -ArtifactRoot $ArtifactRoot -BatchReceipt $BatchReceipt -CaseName $CaseName
$artifactLock=Enter-AndroidArtifactLock $roots.Root
$caseLock=$null
$caseAttempt=$null
try {
    Assert-AndroidCaseInputsSeparate $roots.Directory @($apkInput,$Emulator,$Kernel,$Ramdisk,$SystemDirectory,$AndroidSdk,
        $PSScriptRoot,"$repo/scripts/tests","$repo/tests/expected-apps.txt","$repo/tests/common/moderncpp-required.txt")
    $caseLock=Enter-AndroidArtifactLock $roots.Directory
    Clear-AndroidResultAggregates $roots.Root
    $caseAttempt=Start-AndroidCaseAttempt $roots.Directory -DeferArchive
if (!$AndroidSdk) { throw 'Set ANDROID_HOME or pass -AndroidSdk.' }
Assert-AndroidNoEmulatorRunning -Emulator $Emulator -Message 'Another Android emulator is running.'
$adb = (Get-Item -LiteralPath "$AndroidSdk/platform-tools/adb.exe").FullName
$Apk = (Get-Item -LiteralPath $Apk).FullName
$Emulator = (Get-Item -LiteralPath $Emulator).FullName
$Kernel = (Get-Item -LiteralPath $Kernel).FullName
$Ramdisk = (Get-Item -LiteralPath $Ramdisk).FullName
$SystemDirectory = (Resolve-Path -LiteralPath $SystemDirectory).Path
$output=$roots.Directory
$adbEndpoint=Get-AndroidAdbEndpoint
Assert-AndroidCaseInputsSeparate $output @($Apk,$Emulator,$Kernel,$Ramdisk,$SystemDirectory,$AndroidSdk)
$binding=Get-AndroidApi10ApkBinding -Root $roots.Root -Apk $Apk -Abi $Abi -SdkImageId $SdkImageId -RequireManifest ([bool]$BatchReceipt -or $soundCacheTeardown) -RuntimeProbe ([bool]$RuntimeProbe)
$SdkImageId=$binding.sdk_image_id
$logMarker=$null
$receipt = @{
    schema_version=3; case=$CaseName; qualification=$false; scope='single-case';
    apk_manifest_bound=$binding.apk_manifest_bound;apk_manifest_sha256=$binding.apk_manifest_sha256;apk_relative=$binding.apk_relative; package=$Package; process_exit_confirmed=$false;
    termination_policy=$(if ($RuntimeProbe) { 'jni-return' } else { 'natural' }); abi=$Abi; api=10; sdk_image_id=$SdkImageId
    emulator_sha256=(Get-FileHash -LiteralPath $Emulator -Algorithm SHA256).Hash.ToLowerInvariant()
    apk_sha256=$binding.apk_sha256
    adb_endpoint=$adbEndpoint;adb_server_socket=$env:ADB_SERVER_SOCKET; adb_server_port=$env:ANDROID_ADB_SERVER_PORT
    started_utc=$caseAttempt.StartedUtc; completed=$false
}
if ($soundCacheTeardown) { $receipt.diagnostic='qt5-sound-cache-teardown' }
if ($crashHoldDiagnostic) { $receipt.diagnostic='android-post-main-crash-hold' }
if ($BatchReceipt) {
    $BatchReceipt=(Get-Item -LiteralPath $BatchReceipt).FullName
    $batchSha=(Get-FileHash -LiteralPath $BatchReceipt).Hash.ToLowerInvariant()
    $batch=Get-Content -LiteralPath $BatchReceipt -Raw | ConvertFrom-Json
    if ($batch.schema_version -ne 1 -or $batch.batch_id -cnotmatch '^[0-9a-f]{32}$' -or
            $batch.abi -cne $Abi -or $batch.api -ne 10 -or $batch.sdk_image_id -cne $SdkImageId -or
            $batch.run -cne [IO.Path]::GetFileName([IO.Path]::GetDirectoryName($BatchReceipt)) -or
            $batch.apk_manifest_sha256 -cne $binding.apk_manifest_sha256 -or
            $batch.emulator_sha256 -cne $receipt.emulator_sha256 -or
            (Get-FileHash -LiteralPath $BatchReceipt).Hash.ToLowerInvariant() -cne $batchSha) {
        throw 'API10 batch does not match this runner input'
    }
    $receipt.batch_id=$batch.batch_id
    $receipt.batch_receipt_sha256=$batchSha
}
Save-AndroidCaseAttemptHistory $caseAttempt
$receipt.case_attempt_id=$caseAttempt.Id
Write-AndroidCaseReceipt $output $receipt
$serial = 'emulator-5580'
$data = Join-Path $output 'userdata-qemu.img'
Copy-Item -LiteralPath "$SystemDirectory/userdata.img" -Destination $data -Force
Invoke-AndroidTool $adb @('start-server') -Endpoint $adbEndpoint
$arguments = @('-sysdir', $SystemDirectory, '-datadir', $output,
    '-system', "$SystemDirectory/system.img", '-kernel', $Kernel,
    '-ramdisk', $Ramdisk, '-data', $data, '-initdata', "$SystemDirectory/userdata.img",
    '-no-window', '-no-audio', '-no-snapshot', '-no-snapstorage',
    '-skin', '480x320', '-partition-size', '512', '-memory', '256', '-gpu', 'off', '-port', '5580',
    '-no-boot-anim', '-verbose', '-show-kernel')
if ($Abi -eq 'x86') {
    if ($ClassicEmulator) { $arguments += @('-qemu', '-disable-hax', '-cpu', 'qemu32') }
    else { $arguments += @('-no-accel', '-qemu', '-cpu', 'core2duo') }
}
else { $arguments += @('-qemu', '-cpu', 'cortex-a8') }
$receipt.emulator_arguments=@($arguments)
Write-AndroidCaseReceipt $output $receipt
$previousSdkHome = $env:ANDROID_SDK_HOME
try {
    # Classic QEMU otherwise writes emulator-user.ini in the host user's home.
    $env:ANDROID_SDK_HOME = $output
    $emulatorOwner=Start-AndroidOwnedProcess -Program $Emulator -Arguments $arguments -Directory $output -ArtifactRoot $roots.Root -ArtifactLease (Get-AndroidArtifactLockStream $roots.Root) -AdbEndpoint $adbEndpoint
    $process=$emulatorOwner.Process
} finally { $env:ANDROID_SDK_HOME = $previousSdkHome }
try {
    $receipt.host_process_owner_sha256=$emulatorOwner.OwnerSha
    $receipt.host_process_request_sha256=$emulatorOwner.RequestSha
    Write-AndroidCaseReceipt $output $receipt
    Wait-AndroidBoot -Adb $adb -Serial $serial -RunDirectory $output -EmulatorPid $process.Id -EmulatorProcess $process -TimeoutSeconds 180
    Set-AndroidGuestStayAwake -Adb $adb -Serial $serial -RunDirectory $output
    $receipt.guest_power_sha256=(Get-FileHash -LiteralPath "$output/power-before.txt" -Algorithm SHA256).Hash.ToLowerInvariant()
    foreach ($entry in @(
        @('ro.build.version.release', $(if ($Abi -eq 'x86') { '2.3.7' } else { '2.3.3' })),
        @('ro.build.version.sdk', '10'),
        @('ro.product.cpu.abi', $Abi)
    )) {
        $value = ((Invoke-AndroidTool $adb @('-s', $serial, 'shell', 'getprop', $entry[0])) -join '').Trim()
        if ($value -ne $entry[1]) { throw "Unexpected $($entry[0]): $value." }
        "$($entry[0])=$value" | Add-Content -LiteralPath "$output/guest.txt"
    }
    Invoke-AndroidTool $adb @('-s', $serial, 'shell', 'cat', '/proc/cpuinfo') | Set-Content "$output/guest-cpuinfo.txt"
    $guestCpu=Save-AndroidGuestCpuBaseline $output $Abi
    $receipt.guest_cpuinfo_sha256=$guestCpu.guest_cpuinfo_sha256
    $receipt.guest_cpu_baseline_sha256=$guestCpu.guest_cpu_baseline_sha256
    if ($NativeSensorFixture) {
        $process.Refresh()
        if ($process.HasExited) { throw 'The owned emulator stopped before sensor inputs' }
        Invoke-AndroidTool python @("$PSScriptRoot/android-sensor-inputs.py",'--directory',$output,
            '--request-sha256',$emulatorOwner.RequestSha)
        $receipt.native_sensor_fixture='nonparallel-compass-v1'
        $receipt.native_sensor_fixture_sha256=(Get-FileHash -LiteralPath "$output/native-sensor-inputs.json").Hash.ToLowerInvariant()
    }
    Invoke-AndroidTool $adb @('-s', $serial, 'shell', 'input', 'keyevent', '82')
    Invoke-AndroidTool $adb @('-s', $serial, 'shell', 'logcat', '-c')
    Assert-AndroidApi10ApkBinding $roots.Root $Apk $binding
    # Classic software x86 can transfer these ordinary APKs below120 KiB/s.
    # Keep a bounded transfer deadline separate from app completion/exit checks.
    $pushTimeout=if ($Abi -eq 'x86' -and $ClassicEmulator) { 600000 } else { 180000 }
    $receipt.apk_push_timeout_ms=$pushTimeout
    Write-AndroidCaseReceipt $output $receipt
    $pushTimer=[Diagnostics.Stopwatch]::StartNew()
    $pushOutput=@(Invoke-AndroidTool $adb @('-s',$serial,'push',$Apk,'/data/local/longreach-example.apk') `
        -Endpoint $adbEndpoint -TimeoutMilliseconds $pushTimeout)
    $push=@{schema_version=1;apk_sha256=$binding.apk_sha256;bytes=(Get-Item -LiteralPath $Apk).Length;
        timeout_ms=$pushTimeout;elapsed_ms=$pushTimer.ElapsedMilliseconds;output=$pushOutput}
    Write-AndroidOwnedProcessJson "$output/apk-push.json" $push
    $receipt.apk_push_evidence_sha256=(Get-FileHash -LiteralPath "$output/apk-push.json").Hash.ToLowerInvariant()
    Write-AndroidCaseReceipt $output $receipt
    $install = Invoke-AndroidTool $adb @('-s', $serial, 'shell', 'pm', 'install', '/data/local/longreach-example.apk')
    Assert-AndroidApi10ApkBinding $roots.Root $Apk $binding
    if (!($install -match '^\s*Success\s*$')) { throw "APK install failed: $install" }
    $logMarker='BEGIN-'+[guid]::NewGuid().ToString('N')
    $logMarker | Set-Content -LiteralPath "$output/log-marker.txt"
    Invoke-AndroidTool $adb @('-s',$serial,'shell','log','-p','i','-t','LongreachCase',$logMarker)
    $receipt.log_marker=$logMarker
    if ($StrictCxx23) { $ApplicationArguments = '--modern-cpp' }
    $launchArguments = @('-s', $serial, 'shell', 'am', 'start', '-n',
        "$Package/$activity", '--es', 'applicationArguments', (ConvertTo-AndroidShellArgument $ApplicationArguments),
        '--es', 'qtRasterImageDepth', $RasterImageDepth)
    if ($DebugQtPlugins) { $launchArguments += @('--ez', 'debugQtPlugins', 'true') }
    if ($QtQuickBackend -ne 'default') {
        $launchArguments += @('--es', 'qtQuickBackend', $QtQuickBackend)
    }
    $receipt.launch_arguments=@($launchArguments)
    Write-AndroidCaseReceipt $output $receipt
    $launchOutput=@(Invoke-AndroidTool $adb $launchArguments)
    $launchOutput | Set-Content -LiteralPath "$output/launch.txt"
    Assert-AndroidActivityLaunch -Output $launchOutput -Component "$Package/$activity"
    $launchOutput
    $complete = $false
    for ($attempt = 0; $attempt -lt 120; $attempt++) {
        Start-Sleep -Seconds 2
        $process.Refresh()
        if ($process.HasExited) { break }
        $result = @(Invoke-AndroidExitQuery -Adb $adb -Serial $serial -Command @('shell','cat',"/data/data/$Package/files/$completionName") -Directory $output -Name 'native-result' -TimeoutMilliseconds 5000 -AllowNonzero)
        if ($result -match '^\s*[0-9]+\s*$') { $complete = $true; break }
        $logs = @(Invoke-AndroidExitQuery -Adb $adb -Serial $serial -Command @('logcat','-d','-v','brief') -Directory $output -Name 'native-progress' -TimeoutMilliseconds 5000)
        $current=@(Get-AndroidApi21CaseLog -RawLog $logs -Marker $logMarker)
        $lifecycle=Get-AndroidApplicationLifecycle $current $Package
        if ($lifecycle -and $lifecycle.death_line) { break }
    }
    Invoke-AndroidTool $adb @('-s', $serial, 'pull', "/data/data/$Package/files", $output)
    if (!$complete -or !($result -match '^\s*0\s*$')) { throw "Example did not return zero: $result" }
    if (!$RuntimeProbe) {
        $exitProof=Wait-AndroidApplicationExit -Adb $adb -Serial $serial -Directory $output -Package $Package -Marker $logMarker
        $receipt.process_exit_confirmed=$true
        $receipt.process_id=$exitProof.process_id
        $receipt.process_exit_proof_sha256=(Get-FileHash "$output/process-exit.json").Hash.ToLowerInvariant()
    }
    if ($soundCacheTeardown) {
        $soundStdoutHash=(Get-FileHash -LiteralPath "$output/files/$stdoutName" -Algorithm SHA256).Hash.ToLowerInvariant()
        Invoke-AndroidTool python @("$repo/scripts/tests/require-android-sound-cache.py", "$output/files/$stdoutName")
        if ((Get-FileHash -LiteralPath "$output/files/$stdoutName" -Algorithm SHA256).Hash.ToLowerInvariant() -cne $soundStdoutHash) {
            throw 'Sound-cache stdout changed during validation'
        }
        $receipt.diagnostic_stdout_sha256=$soundStdoutHash
    }
    if ($StrictCxx23) {
        Invoke-AndroidTool python @("$repo/scripts/tests/require-modern-cpp.py", "$output/files/$stdoutName")
    }
    $report = @(Get-Content -LiteralPath "$output/files/$stdoutName")
    $knownApps = @(Get-Content -LiteralPath "$repo/tests/expected-apps.txt" |
        Where-Object { $_ -match '^[a-z]' -and $_ -ne 'smoke-runner' })
    $appName = [IO.Path]::GetFileNameWithoutExtension($Apk)
    if (!$StrictCxx23 -and $ApplicationArguments -in @('--selftest', '--gallery-selftest') -and $appName -in $knownApps) {
        if (!($report -match '^---- [^:]+: [1-9][0-9]* passed, 0 failed, [0-9]+ skipped ----\s*$')) {
            throw 'The APK returned zero but did not report successful smoke checks.'
        }
    }
    if ($CaseName) {
        Invoke-AndroidTool python @("$repo/scripts/run/android-baselines.py", '--qt', '5', '--api', '10', '--abi', $Abi, '--case', $CaseName, '--report', "$output/files/$stdoutName")
    }
    Assert-AndroidGuestCpuBinding $output $guestCpu
    Assert-AndroidApi10ApkBinding $roots.Root $Apk $binding
    if ($receipt.apk_sha256 -ne (Get-FileHash -LiteralPath $Apk -Algorithm SHA256).Hash.ToLowerInvariant()) {
        throw 'APK changed while the guest was running'
    }
    if ($RuntimeProbe) {
        $raw=@(Invoke-AndroidExitQuery -Adb $adb -Serial $serial -Command @('logcat','-d','-v','brief') -Directory $output -Name 'probe-logcat' -TimeoutMilliseconds 5000)
        $raw | Set-Content -LiteralPath "$output/logcat-raw.log"
        $logs=@(Get-AndroidApi21CaseLog -RawLog $raw -Marker $logMarker)
        $logs | Set-Content -LiteralPath "$output/logcat.log"
    } else { $logs=@(Get-Content -LiteralPath "$output/logcat.log") }
    if ($logs -match 'FATAL EXCEPTION|Fatal signal|exiting due to signal|terminated by signal|VM aborting') { throw 'Fatal cleanup error; see logcat.log' }
} finally {
    try {
        $finalLog=@(Invoke-AndroidExitQuery -Adb $adb -Serial $serial -Command @('logcat','-d','-v','brief') -Directory $output -Name 'final-logcat' -TimeoutMilliseconds 5000)
        $finalLog | Set-Content -LiteralPath "$output/final-logcat.log" -Encoding utf8
        if ($logMarker) {
            $late=@(Get-AndroidApi21CaseLog -RawLog $finalLog -Marker $logMarker)
            $lifecycle=Get-AndroidApplicationLifecycle $late $Package
            if ($receipt.process_exit_confirmed -and (!$lifecycle -or !$lifecycle.death_line -or $lifecycle.process_id -ne $receipt.process_id)) { throw 'Final log lost its application exit evidence' }
        }
    } finally { $hostTree=Stop-AndroidOwnedProcess $emulatorOwner }
}

if ($receipt.host_process_owner_sha256 -cne $hostTree.host_process_owner_sha256 -or
        $receipt.host_process_request_sha256 -cne $hostTree.host_process_request_sha256) { throw 'Owned process tree changed after its case' }
foreach ($field in $hostTree.PSObject.Properties) { $receipt[$field.Name]=$field.Value }
$receipt.emulator_exit_confirmed=$true
$receipt.final_logcat_sha256=(Get-FileHash "$output/final-logcat.log").Hash.ToLowerInvariant()
if ($BatchReceipt -and (Get-FileHash -LiteralPath $BatchReceipt).Hash.ToLowerInvariant() -cne $batchSha) {
    throw 'API10 batch changed while the guest was running'
}
Assert-AndroidApi10ApkBinding $roots.Root $Apk $binding
Assert-AndroidGuestCpuBinding $output $guestCpu
$stdoutHash=(Get-FileHash -LiteralPath "$output/files/$stdoutName" -Algorithm SHA256).Hash.ToLowerInvariant()
if ($soundCacheTeardown -and $stdoutHash -cne $receipt.diagnostic_stdout_sha256) {
    throw 'Sound-cache stdout changed after validation'
}
if ($NativeSensorFixture -and $receipt.native_sensor_fixture_sha256 -cne
        (Get-FileHash -LiteralPath "$output/native-sensor-inputs.json").Hash.ToLowerInvariant()) {
    throw 'Native sensor input record changed during the run'
}
$receipt.completed=$true
$receipt.stdout_sha256=$stdoutHash
$receipt.finished_utc=[DateTime]::UtcNow.ToString('o')
Write-AndroidCaseReceipt $output $receipt
[IO.File]::Delete($caseAttempt.Pending)
$report
} catch {
    $caseFailure=$_
    if ($caseAttempt) { try { Write-AndroidCaseAttemptFailure $caseAttempt $caseFailure.Exception.Message } catch { } }
    throw $caseFailure
} finally {
    if ($caseLock) { $caseLock.Dispose() }
    if ($artifactLock) { $artifactLock.Dispose() }
}
