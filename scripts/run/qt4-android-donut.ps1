# SPDX-License-Identifier: GPL-3.0-or-later

param(
    [string] $InputDirectory,
    [string] $OutputDirectory,
    [string] $AndroidSdk = $env:ANDROID_HOME,
    [ValidateSet('bootstrap', 'strict', 'core', 'quick', 'selftest', 'graphics', 'network', 'painting')] [string[]] $Profiles = @('bootstrap', 'strict', 'core', 'quick', 'selftest', 'graphics', 'network', 'painting')
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/android/android-emulator-state.ps1"
$repo = (Resolve-Path "$PSScriptRoot/../..").Path
. "$repo/scripts/build/qt4-android/host.ps1"
. "$PSScriptRoot/android/android-adb.ps1"
if (!$InputDirectory) { $InputDirectory = Join-Path $repo 'downloads/android-donut' }
if (!$OutputDirectory) { $OutputDirectory = Join-Path $repo 'artifacts/qt4-android-donut' }
if (!$AndroidSdk) { throw 'Set ANDROID_HOME or pass -AndroidSdk.' }
$adb = (Get-Item -LiteralPath "$AndroidSdk/platform-tools/adb.exe").FullName
$output = (Resolve-Path -LiteralPath $OutputDirectory).Path
$inputs = (Resolve-Path -LiteralPath $InputDirectory).Path
$Profiles=@($Profiles | ForEach-Object { $_.ToLowerInvariant() })
if (!$Profiles.Count) { throw 'At least one API4 profile is required' }
if (@($Profiles | Sort-Object -Unique).Count -ne $Profiles.Count) { throw 'Duplicate API4 profile selection' }
. "$repo/scripts/build/android-api21/artifact-lock.ps1"
. "$repo/scripts/run/android/android-owned-process.ps1"
Assert-AndroidOwnedArtifactRootAvailable $output
$artifactLock=Enter-AndroidArtifactLock $output
try {
Clear-AndroidResultAggregates $output
Invoke-DonutCommand python @("$repo/scripts/build/qt4-android/donut-artifacts.py",'check-apks','--root',$output,'--artifact-lease-held')
$nativeManifestSha=(Get-FileHash -LiteralPath "$output/donut-native-manifest.json" -Algorithm SHA256).Hash.ToLowerInvariant()
$apkManifestSha=(Get-FileHash -LiteralPath "$output/donut-apk-manifest.json" -Algorithm SHA256).Hash.ToLowerInvariant()
$apkManifest=Get-Content -LiteralPath "$output/donut-apk-manifest.json" -Raw | ConvertFrom-Json
$nativeManifest=Get-Content -LiteralPath "$output/donut-native-manifest.json" -Raw | ConvertFrom-Json
$installedSdk=$null -ne $nativeManifest.PSObject.Properties['installed_sdk']
function Assert-DonutRunGeneration([string]$Profile) {
    Get-AndroidVerifiedHash "$output/donut-native-manifest.json" $nativeManifestSha | Out-Null
    Get-AndroidVerifiedHash "$output/donut-apk-manifest.json" $apkManifestSha | Out-Null
    $package=@($apkManifest.packages | Where-Object { $_.profile -ceq $Profile })
    if ($package.Count -ne 1 -or $package[0].apk -cne "$Profile.apk") { throw 'Missing API4 profile in completed generation' }
    Get-AndroidVerifiedHash "$output/$Profile.apk" $package[0].sha256 | Out-Null
    return $package[0]
}
function Write-DonutRunReceipt([string]$Directory,$Receipt) {
    $path=Join-Path $Directory 'run-inputs.json'
    $temporary=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try {
        [IO.File]::WriteAllText($temporary,($Receipt | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporary,$path,$true)
    } finally { [IO.File]::Delete($temporary) }
}
foreach ($profile in $Profiles) { Assert-DonutRunGeneration $profile | Out-Null }
$sdk = Join-Path $output 'inputs'

Assert-AndroidNoEmulatorRunning -Message 'An Android emulator is already running.'
$jar = Expand-DonutInput "$inputs/android-1.6_r03-linux.zip" `
    'a8c4e3b32269c6b04c2adeabd112fce42f292dab1a40ef3b08ea7d4212be0df4' $sdk 'android-1.6_r03-linux/android.jar'
$emulator = Expand-DonutInput "$inputs/tools_r24.4.1-windows.zip" `
    '74fe511d80d28678f2250f89b63d0d8e5ba80428cb2345279fa019183fa0476f' $sdk 'tools/emulator-arm.exe'
$system = Join-Path (Split-Path $jar) 'images'
$serial = 'emulator-5580'
$expected = @{
    bootstrap = 'Native probe returned 42'
    strict = 'Native probe returned 0'
    core = 'Native probe returned 0'
}
$suites = @{
    selftest = 'qt-selftest'
    graphics = 'graphics'
    network = 'network-gui'
    painting = 'painting-lab'
}
$quickChecks = @(
    'PASS: qrc and first frame',
    'PASS: Android tap updates QML and frame',
    'PASS: Android pause and resume preserve input and rendering',
    'PASS: shared Qt Quick Gallery renders and navigates',
    'PASS: shared Widgets Gallery toggles a checkbox and changes tabs'
)

function Invoke-DonutAdb {
    param([string[]]$Arguments,[int]$TimeoutMilliseconds=0,[switch]$AllowNonzero,$Endpoint)
    Invoke-AndroidAdb -Adb $adb -Arguments $Arguments -TimeoutMilliseconds $TimeoutMilliseconds -AllowNonzero:$AllowNonzero -Endpoint $Endpoint
}
function Assert-DonutOwner($Owner) {
    if (!$Owner.Process -or $Owner.Process.HasExited) { throw 'Owned API4 emulator tree exited during the case' }
}
function Read-DonutLog([string]$Directory) {
    $lines=@(Invoke-DonutAdb @('-s',$serial,'shell','logcat','-d','-v','brief') -TimeoutMilliseconds 5000)
    $lines | Set-Content -LiteralPath "$Directory/case-logcat.log" -Encoding utf8
    if (($lines -join "`n") -match 'FATAL EXCEPTION|Fatal signal|exiting due to signal|terminated by signal|VM aborting|\*\*\*\s+\*\*\*\s+\*\*\*') { throw 'Fatal API4 application error' }
    return $lines
}
function Read-DonutProperty([string] $Name) {
    $lines = Invoke-DonutAdb @('-s', $serial, 'shell', 'getprop', $Name)
    return ($lines -join "`n").Trim()
}

function Invoke-DonutRun([string] $Profile) {
    Assert-AndroidNoEmulatorRunning -Message 'An Android emulator is already running.'
    $package=Assert-DonutRunGeneration $Profile
    $apk = (Get-Item -LiteralPath "$output/$Profile.apk").FullName
    $runId=[guid]::NewGuid().ToString('N')
    New-Item -ItemType Directory -Force -Path "$output/run" | Out-Null
    $run = (New-Item -ItemType Directory -Path "$output/run/$Profile-$runId").FullName
    $runReceipt=[ordered]@{schema_version=1;run_id=$runId;qt_major=4;api=4;abi='armeabi';profile=$Profile;
        generation=$apkManifest.generation;apk=$package.apk;apk_sha256=$package.sha256;native_sha256=$package.native_sha256;
        native_manifest_sha256=$nativeManifestSha;apk_manifest_sha256=$apkManifestSha;
        completed=$false;qualification=$false;evidence_scope='api4-jni-resident-diagnostic';host_tree_exit_verified=$false}
    Write-DonutRunReceipt $run $runReceipt
    # The stock frontend writes hardware-qemu.ini/locks into -sysdir.
    # Own those outputs in the attempt, never in the sealed extraction cache.
    $runSystem=(New-Item -ItemType Directory -Path (Join-Path $run 'system')).FullName
    foreach ($imageName in @('kernel-qemu','ramdisk.img','system.img','userdata.img')) {
        $stockImage=Join-Path $system $imageName
        $workingImage=Join-Path $runSystem $imageName
        $expectedImageSha=(Get-FileHash -LiteralPath $stockImage -Algorithm SHA256).Hash.ToLowerInvariant()
        Copy-Item -LiteralPath $stockImage -Destination $workingImage
        Get-AndroidVerifiedHash $workingImage $expectedImageSha | Out-Null
    }
    $data = Join-Path $run 'userdata-qemu.img'
    Copy-Item -LiteralPath "$runSystem/userdata.img" -Destination $data
    $adbEndpoint=Get-AndroidAdbEndpoint
    Invoke-DonutAdb @('start-server') -Endpoint $adbEndpoint

    $arguments = @('-sysdir', $runSystem, '-datadir', $run,
        '-system', (Join-Path $runSystem 'system.img'), '-kernel', (Join-Path $runSystem 'kernel-qemu'),
        '-ramdisk', (Join-Path $runSystem 'ramdisk.img'), '-data', $data,
        '-initdata', (Join-Path $runSystem 'userdata.img'), '-no-window', '-no-audio',
        '-no-snapshot', '-no-snapstorage', '-no-skin', '-skin', '320x480',
        '-memory', '128', '-gpu', 'off', '-port', '5580', '-no-boot-anim', '-verbose')
    @{schema_version=1;abi='armeabi';emulator=$emulator;arguments=@($arguments)} |
        ConvertTo-Json -Depth 4 | Set-Content -LiteralPath "$run/emulator-launch.json" -Encoding utf8
    Invoke-DonutCommand python @("$PSScriptRoot/android/android-donut-state.py",'capture','--root',$output,'--run',$run,'--artifact-lease-held')
    $runReceipt.emulator_launch_sha256=(Get-FileHash "$run/emulator-launch.json").Hash.ToLowerInvariant()
    $runReceipt.emulator_media_sha256=(Get-FileHash "$run/emulator-media.json").Hash.ToLowerInvariant()
    Write-DonutRunReceipt $run $runReceipt
    $owner=Start-AndroidOwnedProcess -Program $emulator -Arguments $arguments -Directory $run -ArtifactRoot $output -ArtifactLease (Get-AndroidArtifactLockStream $output) -AdbEndpoint $adbEndpoint
    $hostTree=$null
    try {
        $runReceipt.host_process_owner_sha256=$owner.OwnerSha
        $runReceipt.host_process_request_sha256=$owner.RequestSha
        Write-DonutRunReceipt $run $runReceipt
        $ready = $false
        $bootTimer=[Diagnostics.Stopwatch]::StartNew()
        while ($bootTimer.ElapsedMilliseconds -lt 120000) {
            Assert-DonutOwner $owner
            $budget=[Math]::Max(1,[Math]::Min(5000,120000-[int]$bootTimer.ElapsedMilliseconds))
            $devices=@(Invoke-DonutAdb @('devices') -TimeoutMilliseconds $budget -AllowNonzero)
            if ($devices -match "^$serial\s+device") {
                $budget=[Math]::Max(1,[Math]::Min(5000,120000-[int]$bootTimer.ElapsedMilliseconds))
                $pm=@(Invoke-DonutAdb @('-s',$serial,'shell','pm','path','android') -TimeoutMilliseconds $budget -AllowNonzero)
                if ($pm -match '^package:') { $ready = $true; break }
            }
            Start-Sleep -Seconds 2
        }
        if (!$ready) { throw 'Android package manager did not become ready.' }
        Assert-DonutOwner $owner
        $release = Read-DonutProperty 'ro.build.version.release'
        $api = Read-DonutProperty 'ro.build.version.sdk'
        $abi = Read-DonutProperty 'ro.product.cpu.abi'
        if ($release -ne '1.6' -or $api -ne '4' -or $abi -ne 'armeabi') {
            throw "Unexpected guest: Android $release, API $api, $abi."
        }
        Write-Output "$Profile on Android $release, API $api, $abi"
        Invoke-DonutAdb @('-s', $serial, 'shell', 'logcat', '-c')
        Assert-DonutRunGeneration $Profile | Out-Null
        Assert-DonutOwner $owner
        Invoke-DonutAdb @('-s', $serial, 'push', $apk, '/data/local/tmp-longreach-probe.apk')
        Assert-DonutRunGeneration $Profile | Out-Null
        $install = Invoke-DonutAdb @('-s', $serial, 'shell', 'pm', 'install', '/data/local/tmp-longreach-probe.apk')
        if (!($install -match '^\s*Success\s*$')) { throw "APK install failed: $install" }
        Assert-DonutRunGeneration $Profile | Out-Null
        Assert-DonutOwner $owner

        if ($Profile -eq 'quick') {
            Invoke-DonutAdb @('-s', $serial, 'shell', 'input', 'keyevent', '82')
            $result=@(Invoke-DonutAdb @('-s',$serial,'shell','am','instrument','-w',
                'org.longreachqt.donut.quick/.QuickInstrumentation') -TimeoutMilliseconds 55000)
            $result | Set-Content -LiteralPath "$run/instrumentation.log" -Encoding utf8
            $result | Write-Output
            if (!($result -match '^INSTRUMENTATION_CODE: -1\s*$')) {
                throw 'Android did not report a successful instrumentation run.'
            }
            $report = Invoke-DonutAdb @('-s', $serial, 'shell', 'cat',
                '/data/data/org.longreachqt.donut.quick/files/quick-smoke.txt')
            $report | Set-Content -Encoding utf8 -LiteralPath "$run/quick-smoke-guest.txt"
            foreach ($check in $quickChecks) {
                if ($check -notin $report.Trim()) { throw "Missing Quick test result: $check" }
            }
            $report | Write-Output
        } elseif ($suites.ContainsKey($Profile)) {
            $suite = $suites[$Profile]
            Invoke-DonutAdb @('-s', $serial, 'shell', 'am', 'start', '-n', 'org.longreachqt.donut/.ProbeActivity')
            $complete = @()
            $caseTimer=[Diagnostics.Stopwatch]::StartNew()
            while ($caseTimer.ElapsedMilliseconds -lt 120000) {
                Assert-DonutOwner $owner
                Start-Sleep -Seconds 2
                $logs = @(Read-DonutLog $run)
                $complete = $logs -match 'LongreachDonut.*Native probe returned '
                if ($complete -or ($logs -match 'Process org\.longreachqt\.donut \(pid \d+\) has died')) { break }
            }
            $report = Invoke-DonutAdb @('-s', $serial, 'shell', 'cat',
                '/data/data/org.longreachqt.donut/files/suite.log')
            $report | Set-Content -Encoding utf8 -LiteralPath "$run/$suite-guest.stdout"
            Invoke-DonutCommand python @("$repo/scripts/run/android/android-baselines.py", '--qt', '4', '--api', '4', '--abi', 'armeabi', '--case', $Profile, '--report', "$run/$suite-guest.stdout")
            $report | Write-Output
            $summary = '^---- ' + [regex]::Escape($suite) + ': [1-9][0-9]* passed, 0 failed, \d+ skipped ----\s*$'
            if (!($complete -match 'Native probe returned 0\s*$') -or !($report -match $summary)) {
                throw "The $suite checks did not pass."
            }
        } else {
            Invoke-DonutAdb @('-s', $serial, 'shell', 'am', 'start', '-n', 'org.longreachqt.donut/.ProbeActivity')
            $logs = @()
            $caseTimer=[Diagnostics.Stopwatch]::StartNew()
            while ($caseTimer.ElapsedMilliseconds -lt 30000) {
                Assert-DonutOwner $owner
                Start-Sleep -Seconds 2
                $logs = @(Read-DonutLog $run)
                if ($logs -match 'LongreachDonut.*Native probe returned -?\d+\s*$') { break }
            }
            $logs | Where-Object { $_ -match 'LongreachDonut' }
            if ($Profile -eq 'core' -and !($logs -match 'QtCore 4\.8\.7 PASS')) { throw 'QtCore result was absent.' }
            if ($Profile -eq 'strict') {
                $report = Invoke-DonutAdb @('-s', $serial, 'shell', 'cat',
                    '/data/data/org.longreachqt.donut/files/strict-cxx23.log')
                $report | Set-Content -Encoding utf8 -LiteralPath "$run/strict-cxx23-guest.stdout"
                # Preserve the strict report even when JNI reports a failure.
                if (!($logs -match 'Classic locale check passed')) { throw 'Classic locale result was absent.' }
                Invoke-DonutCommand python @("$repo/scripts/tests/require-modern-cpp.py", "$run/strict-cxx23-guest.stdout")
                if ($installedSdk) { Invoke-DonutCommand python @("$repo/scripts/tests/android/require-armv5-atomic.py", "$run/strict-cxx23-guest.stdout") }
            }
        }
        if ($expected.ContainsKey($Profile) -and !($logs -match [regex]::Escape($expected[$Profile]))) { throw "Expected $Profile probe result was absent." }
        if ($Profile -eq 'quick') { Read-DonutLog $run | Out-Null }
        $outputNames=@('case-logcat.log')
        if ($suites.ContainsKey($Profile)) { $outputNames+="$($suites[$Profile])-guest.stdout" }
        elseif ($Profile -eq 'strict') { $outputNames+='strict-cxx23-guest.stdout' }
        elseif ($Profile -eq 'quick') { $outputNames+=@('instrumentation.log','quick-smoke-guest.txt') }
        $runReceipt.case_outputs=[ordered]@{}
        foreach ($name in $outputNames) { $runReceipt.case_outputs[$name]=(Get-FileHash -LiteralPath (Join-Path $run $name)).Hash.ToLowerInvariant() }
        Write-DonutRunReceipt $run $runReceipt
    } finally {
        try {
            $hostTree=& "$PSScriptRoot/android/android-api21-cleanup.ps1" -Adb $adb -Serial $serial -RunDirectory $run -EmulatorPid $owner.Owner.frontend_pid -RequireFinalLog
        } finally {
            # Always stop the retained tree, including a failed common receipt lookup.
            if ($owner.Process -and !$hostTree) { $hostTree=Stop-AndroidOwnedProcess $owner }
        }
    }
    Assert-DonutRunGeneration $Profile | Out-Null
    foreach ($field in @('host_process_owner_sha256','host_process_request_sha256')) {
        if ($runReceipt[$field] -cne $hostTree.$field) { throw 'API4 host launch identity changed during the case' }
    }
    $runReceipt.host_process_exit_sha256=$hostTree.host_process_exit_sha256
    Write-DonutRunReceipt $run $runReceipt
    Invoke-DonutCommand python @("$PSScriptRoot/android/android-donut-state.py",'complete','--root',$output,'--run',$run,'--artifact-lease-held')
}

foreach ($profile in $Profiles) { Invoke-DonutRun $profile }
Invoke-DonutCommand python @("$repo/scripts/build/qt4-android/donut-artifacts.py",'check-apks','--root',$output,'--artifact-lease-held')
} finally { if ($artifactLock) { $artifactLock.Dispose() } }
