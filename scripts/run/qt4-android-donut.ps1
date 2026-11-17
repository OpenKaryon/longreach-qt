# SPDX-License-Identifier: GPL-3.0-or-later

param(
    [string] $InputDirectory,
    [string] $OutputDirectory,
    [string] $AndroidSdk = $env:ANDROID_HOME,
    [ValidateSet('bootstrap', 'strict', 'core', 'quick', 'selftest', 'graphics', 'network', 'painting')] [string[]] $Profiles = @('bootstrap', 'strict', 'core', 'quick', 'selftest', 'graphics', 'network', 'painting')
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot/../..").Path
. "$repo/scripts/build/qt4-android/host.ps1"
if (!$InputDirectory) { $InputDirectory = Join-Path $repo 'downloads/android-donut' }
if (!$OutputDirectory) { $OutputDirectory = Join-Path $repo 'artifacts/qt4-android-donut' }
if (!$AndroidSdk) { throw 'Set ANDROID_HOME or pass -AndroidSdk.' }
$adb = (Get-Item -LiteralPath "$AndroidSdk/platform-tools/adb.exe").FullName
$output = (Resolve-Path -LiteralPath $OutputDirectory).Path
$inputs = (Resolve-Path -LiteralPath $InputDirectory).Path
$sdk = Join-Path $output 'inputs'

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

function Read-DonutProperty([string] $Name) {
    $lines = Invoke-DonutCommand $adb @('-s', $serial, 'shell', 'getprop', $Name)
    return ($lines -join "`n").Trim()
}

function Invoke-DonutRun([string] $Profile) {
    if (Get-Process -Name emulator-arm, emulator, qemu-system-armel -ErrorAction SilentlyContinue) {
        throw 'An Android emulator is already running.'
    }
    $apk = (Get-Item -LiteralPath "$output/$Profile.apk").FullName
    $run = (New-Item -ItemType Directory -Force -Path "$output/run/$Profile").FullName
    $data = Join-Path $run 'userdata-qemu.img'
    Copy-Item -LiteralPath "$system/userdata.img" -Destination $data -Force
    Invoke-DonutCommand $adb @('start-server')

    $arguments = @('-sysdir', $system, '-datadir', $run,
        '-system', "$system/system.img", '-kernel', "$system/kernel-qemu",
        '-ramdisk', "$system/ramdisk.img", '-data', $data,
        '-initdata', "$system/userdata.img", '-no-window', '-no-audio',
        '-no-snapshot', '-no-snapstorage', '-no-skin', '-skin', '320x480',
        '-memory', '128', '-gpu', 'off', '-port', '5580', '-no-boot-anim', '-verbose') |
        ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }
    $process = Start-Process -FilePath $emulator -ArgumentList $arguments -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput "$run/stdout.log" -RedirectStandardError "$run/stderr.log"
    try {
        $ready = $false
        for ($attempt = 0; $attempt -lt 60; $attempt++) {
            $process.Refresh()
            if ($process.HasExited) { throw "Emulator exited with code $($process.ExitCode)." }
            if ((& $adb devices) -match "^$serial\s+device") {
                $pm = & $adb -s $serial shell pm path android 2>&1
                if ($pm -match '^package:') { $ready = $true; break }
            }
            Start-Sleep -Seconds 2
        }
        if (!$ready) { throw 'Android package manager did not become ready.' }
        $release = Read-DonutProperty 'ro.build.version.release'
        $api = Read-DonutProperty 'ro.build.version.sdk'
        $abi = Read-DonutProperty 'ro.product.cpu.abi'
        if ($release -ne '1.6' -or $api -ne '4' -or $abi -ne 'armeabi') {
            throw "Unexpected guest: Android $release, API $api, $abi."
        }
        Write-Output "$Profile on Android $release, API $api, $abi"
        Invoke-DonutCommand $adb @('-s', $serial, 'shell', 'logcat', '-c')
        Invoke-DonutCommand $adb @('-s', $serial, 'push', $apk, '/data/local/tmp-longreach-probe.apk')
        $install = Invoke-DonutCommand $adb @('-s', $serial, 'shell', 'pm', 'install', '/data/local/tmp-longreach-probe.apk')
        if (!($install -match '^\s*Success\s*$')) { throw "APK install failed: $install" }

        if ($Profile -eq 'quick') {
            Invoke-DonutCommand $adb @('-s', $serial, 'shell', 'input', 'keyevent', '82')
            $instrument = Start-Process -FilePath $adb -ArgumentList @('-s', $serial, 'shell', 'am', 'instrument', '-w',
                'org.longreachqt.donut.quick/.QuickInstrumentation') -WindowStyle Hidden -PassThru `
                -RedirectStandardOutput "$run/instrumentation.log" -RedirectStandardError "$run/instrumentation-error.log"
            if (!$instrument.WaitForExit(55000)) {
                Stop-Process -Id $instrument.Id -ErrorAction SilentlyContinue
                throw 'Android instrumentation timed out.'
            }
            $result = Get-Content -LiteralPath "$run/instrumentation.log"
            $result | Write-Output
            if ($instrument.ExitCode -ne 0 -or !($result -match '^INSTRUMENTATION_CODE: -1\s*$')) {
                throw 'Android did not report a successful instrumentation run.'
            }
            $report = Invoke-DonutCommand $adb @('-s', $serial, 'shell', 'cat',
                '/data/data/org.longreachqt.donut.quick/files/quick-smoke.txt')
            $report | Set-Content -Encoding utf8 -LiteralPath "$run/quick-smoke-guest.txt"
            foreach ($check in $quickChecks) {
                if ($check -notin $report.Trim()) { throw "Missing Quick test result: $check" }
            }
            $report | Write-Output
        } elseif ($suites.ContainsKey($Profile)) {
            $suite = $suites[$Profile]
            Invoke-DonutCommand $adb @('-s', $serial, 'shell', 'am', 'start', '-n', 'org.longreachqt.donut/.ProbeActivity')
            $complete = @()
            for ($attempt = 0; $attempt -lt 60; $attempt++) {
                Start-Sleep -Seconds 2
                $logs = & $adb -s $serial shell logcat -d -v brief
                $complete = $logs -match 'LongreachDonut.*Native probe returned '
                if ($complete -or ($logs -match 'Process org\.longreachqt\.donut \(pid \d+\) has died')) { break }
            }
            $report = Invoke-DonutCommand $adb @('-s', $serial, 'shell', 'cat',
                '/data/data/org.longreachqt.donut/files/suite.log')
            $report | Set-Content -Encoding utf8 -LiteralPath "$run/$suite-guest.stdout"
            $report | Write-Output
            $summary = '^---- ' + [regex]::Escape($suite) + ': [1-9][0-9]* passed, 0 failed, \d+ skipped ----\s*$'
            if (!($complete -match 'Native probe returned 0\s*$') -or !($report -match $summary)) {
                throw "The $suite checks did not pass."
            }
        } else {
            Invoke-DonutCommand $adb @('-s', $serial, 'shell', 'am', 'start', '-n', 'org.longreachqt.donut/.ProbeActivity')
            $logs = @()
            for ($attempt = 0; $attempt -lt 15; $attempt++) {
                Start-Sleep -Seconds 2
                $logs = & $adb -s $serial shell logcat -d -v brief
                if ($logs -match [regex]::Escape($expected[$Profile])) { break }
            }
            if (!($logs -match [regex]::Escape($expected[$Profile]))) { throw "Expected $Profile probe result was absent." }
            $logs | Where-Object { $_ -match 'LongreachDonut' }
            if ($Profile -eq 'core' -and !($logs -match 'QtCore 4\.8\.7 PASS')) { throw 'QtCore result was absent.' }
            if ($Profile -eq 'strict') {
                if (!($logs -match 'Classic locale check passed')) { throw 'Classic locale result was absent.' }
                $report = Invoke-DonutCommand $adb @('-s', $serial, 'shell', 'cat',
                    '/data/data/org.longreachqt.donut/files/strict-cxx23.log')
                $report | Set-Content -Encoding utf8 -LiteralPath "$run/strict-cxx23-guest.stdout"
                Invoke-DonutCommand python @("$repo/scripts/tests/require-modern-cpp.py", "$run/strict-cxx23-guest.stdout")
            }
        }
    } finally {
        try {
            & $adb -s $serial shell logcat -d -v brief | Set-Content -LiteralPath "$run/logcat.log"
        } finally {
            $process.Refresh()
            if (!$process.HasExited) {
                & $adb -s $serial emu kill 2>$null | Out-Null
                if (!$process.WaitForExit(7000)) {
                    Stop-Process -Id $process.Id
                    $process.WaitForExit()
                }
            }
        }
    }
}

foreach ($profile in $Profiles) { Invoke-DonutRun $profile }
