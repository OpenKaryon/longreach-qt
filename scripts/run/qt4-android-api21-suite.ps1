# SPDX-License-Identifier: GPL-3.0-or-later
param([ValidateSet('x86_64')][string]$Abi='x86_64',
      [ValidateSet('bootstrap','strict','core','quick','selftest','graphics','network','painting','widgets','multimedia','gl','qml')][string[]]$Profiles,
      [string]$RunName='sdk-suite', [string]$AndroidSdk=$env:ANDROID_HOME, [string]$OutputDirectory)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path "$PSScriptRoot/../..").Path
. "$PSScriptRoot/android-api21-log.ps1"
if (!$AndroidSdk) { throw 'Set ANDROID_HOME or pass -AndroidSdk' }
if (!$OutputDirectory) { $OutputDirectory="$repo/artifacts/qt4-android-lollipop-$Abi" }
$root=(Resolve-Path -LiteralPath $OutputDirectory).Path
$adb=(Get-Item "$AndroidSdk/platform-tools/adb.exe").FullName
$serial='emulator-5582'
$requiredProfiles=@('bootstrap','strict','core','selftest','widgets','graphics','painting','multimedia','gl','qml','network','quick')
$fullRun=!$Profiles
if (!$Profiles) { $Profiles=$requiredProfiles }
if (@($Profiles | Sort-Object -Unique).Count -ne $Profiles.Count) { throw 'Duplicate Qt4 test profile' }
$packages=@(Get-Content "$root/apk-packages.json" -Raw | ConvertFrom-Json)
$sdkId=(Get-Content "$root/sdk-image-id.txt" -Raw).Trim()
if ($sdkId -notmatch '^sha256:[0-9a-f]{64}$' -or (Get-Content "$root/examples-sdk-image-id.txt" -Raw).Trim() -ne $sdkId) { throw 'SDK/example identities differ' }
foreach ($profile in $Profiles) {
    $package=@($packages | Where-Object { $_.profile -eq $profile })
    if ($package.Count -ne 1 -or $package[0].abi -ne $Abi -or $package[0].api -ne 21 -or $package[0].sdk_image_id -ne $sdkId -or
            $package[0].apk -ne "$profile.apk" -or (Get-FileHash "$root/$profile.apk" -Algorithm SHA256).Hash.ToLowerInvariant() -ne $package[0].sha256) {
        throw "APK does not match the current SDK/package manifest: $profile"
    }
}
$quickChecks=@('PASS: qrc and first frame','PASS: Android tap updates QML and frame',
    'PASS: Android pause and resume preserve input and rendering',
    'PASS: shared Qt Quick Gallery renders and navigates',
    'PASS: shared Widgets Gallery toggles a checkbox and changes tabs')
$labels=@{selftest='qt-selftest';widgets='widgets-gallery';graphics='graphics';painting='painting-lab';multimedia='multimedia-lab';gl='gl-heavy';qml='quick-qml';network='network-gui'}
if (Get-Process -Name emulator,emulator-arm,emulator64-x86,qemu-system-x86_64,qemu-system-x86_64-headless,qemu-system-aarch64 -ErrorAction SilentlyContinue) { throw 'Stop the existing emulator before this suite' }
foreach ($profile in $Profiles) { if (!(Test-Path "$root/$profile.apk")) { throw "Missing APK: $profile" } }
function Invoke-Adb([string[]]$Arguments) {
    $text=& $adb -s $serial @Arguments
    if ($LASTEXITCODE) { throw "adb failed: $Arguments" }
    return $text
}
& "$repo/scripts/fetch/qt6-android.ps1" -Scope test -Abi $Abi -AndroidSdk $AndroidSdk
& python "$repo/scripts/build/qt6-android/prepare-emulator.py" --repo $repo --output $root --abi $Abi
if ($LASTEXITCODE) { throw 'Cannot prepare pinned API21 guest' }
& "$PSScriptRoot/qt6-android-start.ps1" -OutputDirectory $root -Abi $Abi -RunName $RunName -Emulator "$root/media/emulator-32.1.11/emulator/emulator.exe"
$run="$root/$RunName"
$outcomes=[Collections.Generic.List[object]]::new()
try {
    $ready=$false
    for ($attempt=0; $attempt -lt 150; $attempt++) {
        if ((& $adb -s $serial shell getprop sys.boot_completed 2>$null) -match '^\s*1\s*$') { $ready=$true; break }
        if ($attempt % 10 -eq 0) { & $adb reconnect offline | Out-Null }
        Start-Sleep -Seconds 2
    }
    if (!$ready) { throw 'API21 guest did not boot' }
    foreach ($pair in @(@('ro.build.version.sdk','21'),@('ro.build.version.release','5.0.2'),@('ro.product.cpu.abi',$Abi))) {
        $actual=((Invoke-Adb @('shell','getprop',$pair[0])) -join '').Trim()
        if ($actual -ne $pair[1]) { throw "Wrong guest: $($pair[0])=$actual" }
    }
    Invoke-Adb @('shell','getprop') | Set-Content "$run/guest-properties.txt"
    Invoke-Adb @('shell','input','keyevent','82') | Out-Null
    foreach ($profile in $Profiles) {
        $case=(New-Item -ItemType Directory -Path "$run/$profile").FullName
        $package=if ($profile -eq 'quick') { 'org.longreachqt.donut.quick' } else { 'org.longreachqt.donut' }
        $apk="$root/$profile.apk"
        $installed=Invoke-Adb @('install','-r',$apk)
        $installed | Set-Content "$case/install.txt"
        if (!($installed -match '^\s*Success\s*$')) { throw "APK install failed: $profile" }
        Invoke-Adb @('shell','am','force-stop',$package) | Out-Null
        $clear=Invoke-Adb @('shell','pm','clear',$package)
        if (!($clear -match '^\s*Success\s*$')) { throw 'Could not reset app data' }
        Invoke-Adb @('logcat','-b','all','-c') | Out-Null
        $marker='BEGIN-'+[guid]::NewGuid().ToString('N')
        $marker | Set-Content "$case/log-marker.txt"
        Invoke-Adb @('shell','log','-p','i','-t','LongreachCase',$marker) | Out-Null
        $complete=$false
        $native=@()
        if ($profile -eq 'quick') {
            $instrument=Start-Process -FilePath $adb -WindowStyle Hidden -PassThru `
                -ArgumentList @('-s',$serial,'shell','am','instrument','-w',"$package/.QuickInstrumentation") `
                -RedirectStandardOutput "$case/instrumentation.log" -RedirectStandardError "$case/instrumentation.stderr"
            if (!$instrument.WaitForExit(120000)) {
                Stop-Process -Id $instrument.Id -ErrorAction SilentlyContinue
                throw 'Qt4 gallery instrumentation timed out'
            }
            $text=Get-Content "$case/instrumentation.log"
            if ($instrument.ExitCode -ne 0 -or !($text -match '^INSTRUMENTATION_CODE: -1\s*$')) { throw 'Qt4 gallery instrumentation failed' }
            $complete=$true
            $native=@('0')
        } else {
            Invoke-Adb @('shell','am','start','-n',"$package/.ProbeActivity") | Set-Content "$case/launch.txt"
            for ($attempt=0; $attempt -lt 90; $attempt++) {
                Start-Sleep -Seconds 2
                $native=@(& $adb -s $serial shell cat "/data/data/$package/files/probe-result.txt" 2>$null)
                if ($native -match '^\s*[0-9]+\s*$') { $complete=$true; break }
                if ($attempt % 5 -eq 0) {
                    $pending=@(Invoke-Adb @('logcat','-d','-v','brief'))
                    $current=@(Get-AndroidApi21CaseLog -RawLog $pending -Marker $marker)
                    if ($current -match 'Fatal signal|FATAL EXCEPTION|VM aborting|terminated by signal|exiting due to signal') { break }
                }
            }
        }
        Start-Sleep -Seconds 2
        $raw=@(Invoke-Adb @('logcat','-d','-v','brief'))
        $raw | Set-Content "$case/logcat-raw.log"
        $log=@(Get-AndroidApi21CaseLog -RawLog $raw -Marker $marker)
        $log | Set-Content "$case/logcat.log"
        & $adb -s $serial pull "/data/data/$package/files" "$case/files" 2>&1 | Set-Content "$case/pull.log"
        $expected=if ($profile -eq 'bootstrap') { '42' } else { '0' }
        $received=($native -join '').Trim()
        if (!$complete -or $received -ne $expected) { throw "$profile native result '$received', expected '$expected'; see captured case files" }
        if ($log -match 'Fatal signal|FATAL EXCEPTION|VM aborting|terminated by signal|exiting due to signal') { throw "$profile crashed; see scoped log" }
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
        if ($profile -eq 'quick') {
            $stdout=Get-Content "$case/files/quick-smoke.txt"
            foreach ($check in $quickChecks) { if ($check -notin $stdout.Trim()) { throw "Missing gallery check: $check" } }
            foreach ($png in @('qml-gallery.png','widgets-gallery.png')) { if (!(Test-Path "$case/files/$png")) { throw "Missing rendered gallery frame: $png" } }
            $passed=$quickChecks.Count
        }
        $outcomes.Add([pscustomobject]@{profile=$profile;native_return=$(if ($profile -ne 'quick') { [int]$expected } else { $null });
            instrumentation_code=$(if ($profile -eq 'quick') { -1 } else { $null });log_marker=$marker;
            passed=$passed;failed=0;skipped=$skipped;summary=$summary;sdk_image_id=$sdkId;
            apk_sha256=(Get-FileHash $apk -Algorithm SHA256).Hash.ToLowerInvariant()})
        $outcomes | ConvertTo-Json -Depth 5 | Set-Content "$run/results.json"
        $completion=if ($profile -eq 'quick') { 'instrumentation code -1' } else { "native return $expected" }
        Write-Output "$profile PASS: $passed passed, 0 failed, $skipped skipped; $completion"
        Invoke-Adb @('shell','am','force-stop',$package) | Out-Null
        $removed=Invoke-Adb @('uninstall',$package)
        if (!($removed -match '^\s*Success\s*$')) { throw 'Cannot release tested APK' }
    }
} finally {
    $owned=[int](Get-Content "$run/emulator.pid")
    & "$PSScriptRoot/android-api21-cleanup.ps1" -Adb $adb -Serial $serial -RunDirectory $run -EmulatorPid $owned
}

if ($fullRun) {
    & python "$repo/scripts/build/qt4-android/collect-api21-results.py" --root $root --run $RunName --abi $Abi
    if ($LASTEXITCODE) { throw 'Incomplete Qt4 API21 suite evidence' }
}
