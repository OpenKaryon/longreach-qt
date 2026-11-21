# SPDX-License-Identifier: GPL-3.0-or-later

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
    [switch] $DebugQtPlugins
)

$ErrorActionPreference = 'Stop'
if ($RuntimeProbe) {
    $StrictCxx23=$true
    if (!$PSBoundParameters.ContainsKey('Package')) { $Package='org.longreachqt.donut' }
}
$completionName=if ($RuntimeProbe) { 'probe-result.txt' } else { 'selftest-result.txt' }
$stdoutName=if ($RuntimeProbe) { 'strict-cxx23.log' } else { 'selftest.stdout' }
$activity=if ($RuntimeProbe) { 'org.longreachqt.donut.ProbeActivity' } else { 'org.longreachqt.examples.SmokeActivity' }

. "$PSScriptRoot/android-wait-boot.ps1"
$repo = (Resolve-Path "$PSScriptRoot/../..").Path
function Invoke-AndroidTool([string] $Program, [string[]] $Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program exited with code $LASTEXITCODE." }
}
function Initialize-AndroidRunDirectory([string] $Directory) {
    $runRoot = (New-Item -ItemType Directory -Force -Path $Directory).FullName
    $reports = Join-Path $runRoot 'files'
    if (Test-Path -LiteralPath $reports) {
        $item = Get-Item -LiteralPath $reports
        $history = Join-Path $runRoot ("previous-" + [guid]::NewGuid())
        if (!$item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
                ![string]::Equals([IO.Path]::GetDirectoryName($item.FullName), $runRoot,
                    [StringComparison]::OrdinalIgnoreCase) -or
                ![string]::Equals([IO.Path]::GetDirectoryName($history), $runRoot,
                    [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to archive reports outside the run directory: $reports"
        }
        New-Item -ItemType Directory -Path $history | Out-Null
        Move-Item -LiteralPath $item.FullName -Destination $history
    }
    # A failed rerun must not leave an earlier successful report as its result.
    [IO.File]::WriteAllText((Join-Path $runRoot 'guest.txt'), '')
    return $runRoot
}

if (!$AndroidSdk) { throw 'Set ANDROID_HOME or pass -AndroidSdk.' }
if (Get-Process -Name emulator-arm, emulator, qemu-system-armel, emulator-x86, emulator64-x86, qemu-system-i386, qemu-system-i386-headless, qemu-system-x86_64, qemu-system-x86_64-headless -ErrorAction SilentlyContinue) {
    throw 'Another Android emulator is running.'
}
$adb = (Get-Item -LiteralPath "$AndroidSdk/platform-tools/adb.exe").FullName
$Apk = (Get-Item -LiteralPath $Apk).FullName
$Emulator = (Get-Item -LiteralPath $Emulator).FullName
$Kernel = (Get-Item -LiteralPath $Kernel).FullName
$Ramdisk = (Get-Item -LiteralPath $Ramdisk).FullName
$SystemDirectory = (Resolve-Path -LiteralPath $SystemDirectory).Path
$output = Initialize-AndroidRunDirectory $OutputDirectory
$serial = 'emulator-5580'
$data = Join-Path $output 'userdata-qemu.img'
Copy-Item -LiteralPath "$SystemDirectory/userdata.img" -Destination $data -Force
Invoke-AndroidTool $adb @('start-server')
$arguments = @('-sysdir', $SystemDirectory, '-datadir', $output,
    '-system', "$SystemDirectory/system.img", '-kernel', $Kernel,
    '-ramdisk', $Ramdisk, '-data', $data, '-initdata', "$SystemDirectory/userdata.img",
    '-no-window', '-no-audio', '-no-snapshot', '-no-snapstorage',
    '-skin', '480x320', '-partition-size', '512', '-memory', '256', '-gpu', 'off', '-port', '5580',
    '-no-boot-anim', '-verbose', '-show-kernel')
if ($Abi -eq 'x86') { $arguments += @('-no-accel', '-qemu', '-cpu', 'core2duo') }
else { $arguments += @('-qemu', '-cpu', 'cortex-a8') }
$arguments = $arguments |
    ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }
$process = Start-Process -FilePath $Emulator -ArgumentList $arguments -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput "$output/emulator.stdout" -RedirectStandardError "$output/emulator.stderr"
try {
    Wait-AndroidBoot -Adb $adb -Serial $serial -RunDirectory $output -EmulatorPid $process.Id -TimeoutSeconds 180
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
    Invoke-AndroidTool $adb @('-s', $serial, 'shell', 'input', 'keyevent', '82')
    Invoke-AndroidTool $adb @('-s', $serial, 'shell', 'logcat', '-c')
    Invoke-AndroidTool $adb @('-s', $serial, 'push', $Apk, '/data/local/longreach-example.apk')
    $install = Invoke-AndroidTool $adb @('-s', $serial, 'shell', 'pm', 'install', '/data/local/longreach-example.apk')
    if (!($install -match '^\s*Success\s*$')) { throw "APK install failed: $install" }
    if ($StrictCxx23) { $ApplicationArguments = '--modern-cpp' }
    $launchArguments = @('-s', $serial, 'shell', 'am', 'start', '-n',
        "$Package/$activity", '--es', 'applicationArguments', $ApplicationArguments,
        '--es', 'qtRasterImageDepth', $RasterImageDepth)
    if ($DebugQtPlugins) { $launchArguments += @('--ez', 'debugQtPlugins', 'true') }
    if ($QtQuickBackend -ne 'default') {
        $launchArguments += @('--es', 'qtQuickBackend', $QtQuickBackend)
    }
    Invoke-AndroidTool $adb $launchArguments
    $complete = $false
    for ($attempt = 0; $attempt -lt 120; $attempt++) {
        Start-Sleep -Seconds 2
        $process.Refresh()
        if ($process.HasExited) { break }
        $result = @(& $adb -s $serial shell cat "/data/data/$Package/files/$completionName" 2>$null)
        if ($result -match '^\s*[0-9]+\s*$') { $complete = $true; break }
        $logs = @(& $adb -s $serial shell logcat -d -v brief)
        $processDied = 'Process ' + [regex]::Escape($Package) + ' \(pid \d+\) has died'
        if ($logs -match 'FATAL EXCEPTION|Fatal signal|exiting due to signal|terminated by signal|VM aborting' -or
                $logs -match $processDied) { break }
    }
    Invoke-AndroidTool $adb @('-s', $serial, 'pull', "/data/data/$Package/files", $output)
    if (!$complete -or !($result -match '^\s*0\s*$')) { throw "Example did not return zero: $result" }
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
    $report
} finally {
    try {
        & $adb -s $serial shell logcat -d -v brief | Set-Content -LiteralPath "$output/logcat.log"
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
