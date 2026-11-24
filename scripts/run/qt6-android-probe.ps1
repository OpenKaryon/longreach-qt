# SPDX-License-Identifier: GPL-3.0-or-later
param([ValidateSet('armeabi-v7a','arm64-v8a','x86','x86_64')][string]$Abi='armeabi-v7a',
      [string]$AndroidSdk=$env:ANDROID_HOME, [Parameter(Mandatory)][string]$OutputDirectory,
      [string]$RunName='cxx23-probe')
$ErrorActionPreference='Stop'
. "$PSScriptRoot/android-wait-boot.ps1"
. "$PSScriptRoot/android-api21-adb.ps1"
. "$PSScriptRoot/android-shell-status.ps1"
. "$PSScriptRoot/android-owned-process.ps1"
. "$PSScriptRoot/../build/android-api21/artifact-lock.ps1"
$repo=(Resolve-Path "$PSScriptRoot/../..").Path
$root=(Resolve-Path -LiteralPath $OutputDirectory).Path
if (!$AndroidSdk) { throw 'Set ANDROID_HOME or pass -AndroidSdk' }
if ($RunName -notmatch '^[a-z0-9-]+$') { throw 'Invalid run directory name' }
$adb=Join-Path $AndroidSdk 'platform-tools/adb.exe'
$probeFiles=@('cxx23-probe','libc++_shared.so','atomic-probe','liblongreach-atomic-a.so','liblongreach-atomic-b.so')
foreach ($name in $probeFiles) {
    if (!(Test-Path -LiteralPath "$root/probe/$name")) { throw "Missing $root/probe/$name" }
}
Assert-AndroidOwnedArtifactRootAvailable $root
$artifactLock=Enter-AndroidArtifactLock $root
try {
Clear-AndroidResultAggregates $root
& "$repo/scripts/fetch/qt6-android.ps1" -Scope test -Abi $Abi -AndroidSdk $AndroidSdk
& python "$repo/scripts/build/qt6-android/prepare-emulator.py" --repo $repo --output $root --abi $Abi
if ($LASTEXITCODE) { throw 'Could not prepare emulator media' }
$relativeEmulator=switch ($Abi) {
    'x86' { 'emulator-32.1.11/emulator/emulator.exe' }
    'x86_64' { 'emulator-32.1.11/emulator/emulator.exe' }
    'arm64-v8a' { 'emulator-25.2.5/tools/emulator.exe' }
    default { 'tools/emulator-arm.exe' }
}
$emulatorOwner=& "$PSScriptRoot/qt6-android-start.ps1" -OutputDirectory $root -Emulator "$root/media/$relativeEmulator" -RunName $RunName -Abi $Abi -PassThru
$run="$root/$RunName"
$serial='emulator-5582'
try {
    @($probeFiles | ForEach-Object {
        [pscustomobject]@{file=$_;sha256=(Get-FileHash "$root/probe/$_" -Algorithm SHA256).Hash.ToLowerInvariant()}
    }) | ConvertTo-Json | Set-Content "$run/probe-inputs.json"
    Wait-AndroidBoot -Adb $adb -Serial $serial -RunDirectory $run -EmulatorPid $emulatorOwner.Process.Id -EmulatorProcess $emulatorOwner.Process
    foreach ($pair in @(@('ro.build.version.sdk','21'),@('ro.build.version.release','5.0.2'),@('ro.product.cpu.abi',$Abi))) {
        $value=((Invoke-AndroidApi21Adb -Adb $adb -Serial $serial -Parameters @('shell','getprop',$pair[0])) -join '').Trim()
        if ($value -ne $pair[1]) { throw "Wrong guest $($pair[0])=$value" }
    }
    Invoke-AndroidApi21Adb -Adb $adb -Serial $serial -Parameters @('shell','getprop') | Set-Content "$run/guest-properties.txt"
    Invoke-AndroidApi21Adb -Adb $adb -Serial $serial -Parameters @('shell','cat','/proc/cpuinfo') | Set-Content "$run/guest-cpuinfo.txt"
    $remote="/data/local/tmp/longreach-cxx23-$Abi"
    Invoke-AndroidSetupCommand -Adb $adb -Serial $serial -Step mkdir -Command "mkdir -p $remote" -OutputPath "$run/setup-mkdir.stdout" | Out-Null
    foreach ($name in $probeFiles) {
        Invoke-AndroidApi21Adb -Adb $adb -Serial $serial -Parameters @('push',"$root/probe/$name","$remote/$name") | Out-Null
    }
    Invoke-AndroidSetupCommand -Adb $adb -Serial $serial -Step cxx23-chmod -Command "chmod 755 $remote/cxx23-probe" -OutputPath "$run/setup-cxx23-chmod.stdout" | Out-Null
    $command="cd $remote && TMPDIR=$remote LD_LIBRARY_PATH=$remote ./cxx23-probe; result=`$?; echo PROBE_EXIT:`$result; exit `$result"
    Invoke-AndroidApi21Adb -Adb $adb -Serial $serial -Parameters @('shell',$command) -TimeoutMilliseconds 180000 | Set-Content "$run/cxx23.stdout"
    $exitCode=$LASTEXITCODE
    Get-Content "$run/cxx23.stdout"
    if ($exitCode -ne 0 -or !(Select-String -LiteralPath "$run/cxx23.stdout" -Pattern '^PROBE_EXIT:0\s*$' -Quiet)) { throw 'Native C++23 probe failed' }
    & python "$repo/scripts/tests/require-modern-cpp.py" "$run/cxx23.stdout"
    if ($LASTEXITCODE) { throw 'C++23 must pass all25 with no SKIP' }
    Invoke-AndroidSetupCommand -Adb $adb -Serial $serial -Step atomic-chmod -Command "chmod 755 $remote/atomic-probe" -OutputPath "$run/setup-atomic-chmod.stdout" | Out-Null
    $command="cd $remote && TMPDIR=$remote LD_LIBRARY_PATH=$remote ./atomic-probe; result=`$?; echo ATOMIC_EXIT:`$result; exit `$result"
    Invoke-AndroidApi21Adb -Adb $adb -Serial $serial -Parameters @('shell',$command) -TimeoutMilliseconds 180000 | Set-Content "$run/atomic.stdout"
    $exitCode=$LASTEXITCODE
    Get-Content -LiteralPath "$run/atomic.stdout"
    if ($exitCode -ne 0) { throw 'Generic atomic ADB client failed' }
    & python "$repo/scripts/tests/require-android-atomic.py" "$run/atomic.stdout"
    if ($LASTEXITCODE) { throw 'Generic cross-DSO atomic runtime behavior failed' }

} finally {
    try {
        & "$PSScriptRoot/android-api21-cleanup.ps1" -Adb $adb -Serial $serial -RunDirectory $run -EmulatorPid $emulatorOwner.Owner.frontend_pid | Out-Null
    } finally {
        # Keep the retained owner usable even if receipt lookup in common cleanup fails.
        if ($emulatorOwner.Process) { Stop-AndroidOwnedProcess $emulatorOwner | Out-Null }
    }
    if (Test-Path -LiteralPath "$run/final-logcat.log") {
        Copy-Item -LiteralPath "$run/final-logcat.log" -Destination "$run/logcat.log"
    }
}
} finally { if ($artifactLock) { $artifactLock.Dispose() } }
