# SPDX-License-Identifier: GPL-3.0-or-later
param([ValidateSet('armeabi-v7a','arm64-v8a','x86_64')][string]$Abi='armeabi-v7a',
      [string]$AndroidSdk=$env:ANDROID_HOME, [Parameter(Mandatory)][string]$OutputDirectory,
      [string]$RunName='cxx23-probe')
$ErrorActionPreference='Stop'
$repo=(Resolve-Path "$PSScriptRoot/../..").Path
$root=(Resolve-Path -LiteralPath $OutputDirectory).Path
if (!$AndroidSdk) { throw 'Set ANDROID_HOME or pass -AndroidSdk' }
$adb=Join-Path $AndroidSdk 'platform-tools/adb.exe'
foreach ($name in @('cxx23-probe','libc++_shared.so')) {
    if (!(Test-Path -LiteralPath "$root/probe/$name")) { throw "Missing $root/probe/$name" }
}
& "$repo/scripts/fetch/qt6-android.ps1" -Scope test -Abi $Abi -AndroidSdk $AndroidSdk
& python "$repo/scripts/build/qt6-android/prepare-emulator.py" --repo $repo --output $root --abi $Abi
if ($LASTEXITCODE) { throw 'Could not prepare emulator media' }
$relativeEmulator=switch ($Abi) {
    'x86_64' { 'emulator-32.1.11/emulator/emulator.exe' }
    'arm64-v8a' { 'emulator-25.2.5/tools/emulator.exe' }
    default { 'tools/emulator-arm.exe' }
}
& "$PSScriptRoot/qt6-android-start.ps1" -OutputDirectory $root -Emulator "$root/media/$relativeEmulator" -RunName $RunName -Abi $Abi
$run="$root/$RunName"
$serial='emulator-5582'
try {
    $ready=$false
    for ($attempt=0; $attempt -lt 150; $attempt++) {
        $ownedId=[int](Get-Content -LiteralPath "$run/emulator.pid")
        if (!(Get-Process -Id $ownedId -ErrorAction SilentlyContinue)) { throw 'Emulator exited during startup' }
        if ($attempt % 10 -eq 0) { & $adb reconnect offline | Out-Null }
        if ((& $adb -s $serial shell getprop sys.boot_completed 2>$null) -match '^\s*1\s*$') { $ready=$true; break }
        Start-Sleep -Seconds 2
    }
    if (!$ready) { throw 'Android API21 did not boot' }
    foreach ($pair in @(@('ro.build.version.sdk','21'),@('ro.build.version.release','5.0.2'),@('ro.product.cpu.abi',$Abi))) {
        $value=((& $adb -s $serial shell getprop $pair[0]) -join '').Trim()
        if ($value -ne $pair[1]) { throw "Wrong guest $($pair[0])=$value" }
    }
    & $adb -s $serial shell getprop | Set-Content "$run/guest-properties.txt"
    $remote="/data/local/tmp/longreach-cxx23-$Abi"
    & $adb -s $serial shell mkdir -p $remote
    if ($LASTEXITCODE) { throw 'Cannot create probe directory' }
    foreach ($name in @('cxx23-probe','libc++_shared.so')) {
        & $adb -s $serial push "$root/probe/$name" "$remote/$name"
        if ($LASTEXITCODE) { throw "Cannot deploy $name" }
    }
    & $adb -s $serial shell chmod 755 "$remote/cxx23-probe"
    $command="cd $remote && TMPDIR=$remote LD_LIBRARY_PATH=$remote ./cxx23-probe; result=`$?; echo PROBE_EXIT:`$result; exit `$result"
    & $adb -s $serial shell $command | Set-Content "$run/cxx23.stdout"
    $exitCode=$LASTEXITCODE
    Get-Content "$run/cxx23.stdout"
    if ($exitCode -ne 0 -or !(Select-String -LiteralPath "$run/cxx23.stdout" -Pattern '^PROBE_EXIT:0\s*$' -Quiet)) { throw 'Native C++23 probe failed' }
    & python "$repo/scripts/tests/require-modern-cpp.py" "$run/cxx23.stdout"
    if ($LASTEXITCODE) { throw 'C++23 must pass all25 with no SKIP' }
} finally {
    & $adb -s $serial logcat -d -v brief 2>$null | Set-Content "$run/logcat.log"
    & $adb -s $serial emu kill 2>$null | Out-Null
    $ownedId=[int](Get-Content -LiteralPath "$run/emulator.pid")
    $process=Get-Process -Id $ownedId -ErrorAction SilentlyContinue
    if ($process -and !$process.WaitForExit(7000)) { throw 'Emulator did not stop; stop the task-owned guest before building' }
}
