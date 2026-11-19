# SPDX-License-Identifier: GPL-3.0-or-later
param([string]$RunName='sdk-suite', [ValidateSet('on','mesa')][string]$Gpu='on',
      [string[]]$CaseNames, [ValidateSet('default','software')][string]$QtQuickBackend='default',
      [string]$AndroidSdk=$env:ANDROID_HOME, [string]$OutputDirectory)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path "$PSScriptRoot/../..").Path
if (!$AndroidSdk) { throw 'Set ANDROID_HOME or pass -AndroidSdk' }
$AndroidSdk=(Resolve-Path -LiteralPath $AndroidSdk).Path
if (!$OutputDirectory) { $OutputDirectory="$repo/artifacts/qt6-android-lollipop" }
$root=(Resolve-Path -LiteralPath $OutputDirectory).Path
$adb="$AndroidSdk/platform-tools/adb.exe"
& python "$repo/scripts/build/android-api21/artifact-manifest.py" check-apks --root $root --qt-major 6 --abi armeabi-v7a
if ($LASTEXITCODE) { throw 'Refusing incomplete or mismatched APK generation' }
if (Get-Process -Name emulator-arm,emulator,qemu-system-armel -ErrorAction SilentlyContinue) {
    throw 'Stop the existing Android emulator before preparing a fresh suite.'
}
$serial = 'emulator-5582'
function Invoke-Adb([string[]]$Parameters) {
    $output = & $adb -s $serial @Parameters
    if ($LASTEXITCODE -ne 0) { throw "adb failed: $Parameters" }
    return $output
}
$apps = @(Get-Content -LiteralPath "$repo/tests/expected-apps.txt" | Where-Object { $_ -match '^[a-z]' -and $_ -ne 'smoke-runner' })
if ($apps.Count -ne 8) { throw 'Expected exactly eight shared applications' }
foreach ($app in $apps) {
    if (!(Test-Path -LiteralPath "$root/apk/$app.apk")) { throw "Missing APK: $app" }
}
& "$repo/scripts/fetch/qt6-android.ps1" -AndroidSdk $AndroidSdk -Scope test
& python "$repo/scripts/build/qt6-android/prepare-emulator.py" --repo $repo --output $root
if ($LASTEXITCODE) { throw 'Could not prepare API21 emulator inputs' }
$emulator="$root/media/tools/emulator-arm.exe"
& "$PSScriptRoot/qt6-android-start.ps1" -OutputDirectory $root -Emulator $emulator -RunName $RunName -Gpu $Gpu
$run = "$root/$RunName"
$outcomes = [Collections.Generic.List[object]]::new()
try {
    & $adb start-server | Out-Null
    & $adb reconnect offline | Out-Null
    $ready = $false
    for ($attempt = 0; $attempt -lt 120; $attempt++) {
        $ownedId = [int](Get-Content -LiteralPath "$run/emulator.pid")
        if (!(Get-Process -Id $ownedId -ErrorAction SilentlyContinue)) { throw 'Emulator exited during startup; see emulator.stdout' }
        if ($attempt -gt 0 -and $attempt % 10 -eq 0) { & $adb reconnect offline | Out-Null }
        if ((& $adb -s $serial shell getprop sys.boot_completed 2>$null) -match '^\s*1\s*$') { $ready = $true; break }
        Start-Sleep -Seconds 2
    }
    if (!$ready) { throw 'API21 emulator did not finish booting' }
    $expected = @{ 'ro.build.version.release'='5.0.2'; 'ro.build.version.sdk'='21'; 'ro.product.cpu.abi'='armeabi-v7a' }
    foreach ($property in $expected.Keys) {
        $value = ((Invoke-Adb @('shell','getprop',$property)) -join '').Trim()
        if ($value -ne $expected[$property]) { throw "Unexpected $property=$value" }
    }
    Invoke-Adb @('shell','getprop') | Set-Content -LiteralPath "$run/guest-properties.txt"
    Invoke-Adb @('shell','input','keyevent','82') | Out-Null
    $cases = @(@{ App='qt-selftest'; Name='strict-cxx23'; Arguments='--modern-cpp'; Strict=$true })
    $cases += @($apps | ForEach-Object { @{ App=$_; Name=$_; Arguments='--selftest'; Strict=$false } })
    $cases += @{ App='widgets-gallery'; Name='widgets-gui'; Arguments='--gallery-selftest'; Strict=$false }
    $cases += @{ App='quick-qml-gallery'; Name='qml-gui'; Arguments='--gallery-selftest'; Strict=$false }
    if ($CaseNames) {
        foreach ($name in $CaseNames) {
            if ($name -notin $cases.Name) { throw "Unknown suite case: $name" }
        }
        $cases = @($cases | Where-Object { $_.Name -in $CaseNames })
    }
    foreach ($case in $cases) {
        $app = $case.App
        $package = 'org.longreachqt.examples.qt6.' + $app.Replace('-','_')
        $destination = "$run/$($case.Name)"
        New-Item -ItemType Directory -Path $destination | Out-Null
        $apk = "$root/apk/$app.apk"
        $install = Invoke-Adb @('install','-r',$apk)
        $install | Set-Content -LiteralPath "$destination/install.txt"
        if (!($install -match '^\s*Success\s*$')) { throw "APK install failed: $app" }
        Invoke-Adb @('shell','am','force-stop',$package) | Out-Null
        $clear = Invoke-Adb @('shell','pm','clear',$package)
        if (!($clear -match '^\s*Success\s*$')) { throw "Could not reset previous app reports: $package" }
        Invoke-Adb @('logcat','-c') | Out-Null
        $launchArguments = @('shell','am','start','-n',"$package/org.longreachqt.examples.SmokeActivity",'--es','applicationArguments',$case.Arguments)
        if ($QtQuickBackend -ne 'default') {
            $launchArguments += @('--es','qtQuickBackend',$QtQuickBackend)
        }
        Invoke-Adb $launchArguments | Set-Content -LiteralPath "$destination/launch.txt"
        $complete = $false
        $nativeResult = @()
        for ($attempt = 0; $attempt -lt 300; $attempt++) {
            Start-Sleep -Seconds 2
            $nativeResult = @(& $adb -s $serial shell cat "/data/data/$package/files/selftest-result.txt" 2>$null)
            if ($nativeResult -match '^\s*[0-9]+\s*$') { $complete = $true; break }
            if ($attempt % 5 -eq 0) {
                $pendingLog = @(& $adb -s $serial logcat -d -v brief)
                $died = 'Process ' + [regex]::Escape($package) + ' \(pid \d+\) has died'
                if ($pendingLog -match 'FATAL EXCEPTION|Fatal signal|exiting due to signal|terminated by signal|VM aborting' -or $pendingLog -match $died) { break }
            }
        }
        # A success marker must not conceal a native crash during Qt cleanup.
        Start-Sleep -Seconds 2
        $log = @(Invoke-Adb @('logcat','-d','-v','brief'))
        $log | Set-Content -LiteralPath "$destination/logcat.log"
        & $adb -s $serial pull "/data/data/$package/files" "$destination/files" 2>&1 | Set-Content -LiteralPath "$destination/pull.log"
        if (!$complete -or !($nativeResult -match '^\s*0\s*$')) { throw "$($case.Name) did not complete with zero: $nativeResult" }
        if ($log -match 'FATAL EXCEPTION|Fatal signal|exiting due to signal|terminated by signal|VM aborting') { throw "$($case.Name) crashed; see logcat.log" }
        $stdout = "$destination/files/selftest.stdout"
        if (!(Test-Path -LiteralPath $stdout)) { throw "$($case.Name) returned zero without its report" }
        $report = Get-Content -LiteralPath $stdout
        if ($case.Strict) {
            & python "$repo/scripts/tests/require-modern-cpp.py" $stdout
            if ($LASTEXITCODE -ne 0) { throw 'C++23 must pass exactly25 checks without SKIP' }
        } elseif (!($report -match '^---- [^:]+: [1-9][0-9]* passed, 0 failed, [0-9]+ skipped ----\s*$')) {
            throw "$($case.Name) has no successful ordinary summary"
        }
        $summary = @($report | Where-Object { $_ -match 'passed,.*failed,.*skipped' })
        $outcomes.Add([pscustomobject]@{ name=$case.Name; app=$app; arguments=$case.Arguments; result=0; summary=$summary; apk_sha256=(Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant(); finished_utc=[DateTime]::UtcNow.ToString('o') })
        $outcomes | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "$run/results.json"
        Write-Output "$($case.Name): $($summary -join ' ')"
        Invoke-Adb @('shell','am','force-stop',$package) | Out-Null
        # This is a disposable task-owned guest. Release extracted native
        # libraries between cases; all reports and exact APKs remain on host.
        $removed = Invoke-Adb @('uninstall',$package)
        if (!($removed -match '^\s*Success\s*$')) { throw "Could not release tested APK: $package" }
    }
} finally {
    & $adb -s $serial logcat -d -v brief 2>$null | Set-Content -LiteralPath "$run/final-logcat.log"
    & $adb -s $serial emu kill 2>$null | Out-Null
    $ownedId = [int](Get-Content -LiteralPath "$run/emulator.pid")
    $process = Get-Process -Id $ownedId -ErrorAction SilentlyContinue
    if ($process -and !$process.WaitForExit(7000)) {
        Stop-Process -Id $ownedId
        $process.WaitForExit()
    }
}

if (!$CaseNames) {
    & python "$repo/scripts/build/qt6-android/collect-results.py" --root $root --run $RunName
    if ($LASTEXITCODE) { throw 'Incomplete API21 suite evidence' }
}
