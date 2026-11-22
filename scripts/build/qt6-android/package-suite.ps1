# SPDX-License-Identifier: GPL-3.0-or-later

param([ValidateSet('armeabi-v7a','arm64-v8a','x86','x86_64')][string]$Abi = 'armeabi-v7a', [Parameter(Mandatory)][string]$AndroidSdk, [Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path "$PSScriptRoot/../../..").Path
$root=(Resolve-Path -LiteralPath $OutputDirectory).Path
 . "$repo/scripts/build/android-api21/artifact-lock.ps1"
$artifactLock=Enter-AndroidArtifactLock $root
try {
$apps=@(Get-Content "$repo/tests/expected-apps.txt" | Where-Object { $_ -match '^[a-z]' -and $_ -ne 'smoke-runner' })
if ($apps.Count -ne 8) { throw 'Expected eight applications' }
# Validate every input before signing or replacing any APK. No SDK image is needed.
foreach ($relative in @('libc++_shared.so','sdk-packaging/jar/Qt6Android.jar',
        'sdk-packaging/src/android/java/src','sdk-packaging/src/android/java/res')) {
    if (!(Test-Path -LiteralPath "$root/$relative")) {
        throw "Missing packaging input: $relative. Run qt6-android.ps1 -Mode examples first."
    }
}
foreach ($app in $apps) {
    foreach ($relative in @("libs/$Abi/lib${app}_$Abi.so", 'res/values/libs.xml')) {
        if (!(Test-Path -LiteralPath "$root/deployment/$app/$relative")) {
            throw "Missing deployment for $app ($relative). Run qt6-android.ps1 -Mode examples first."
        }
    }
}
& python "$repo/scripts/build/android-api21/artifact-manifest.py" check-examples --root $root --qt-major 6 --abi $Abi
if ($LASTEXITCODE) { throw 'Packaging requires a complete, unchanged example generation' }
$javac=(Get-Command javac.exe,javac -ErrorAction SilentlyContinue | Select-Object -First 1).Source
& python "$repo/scripts/build/android-api21/artifact-manifest.py" begin-apks --root $root --qt-major 6 --abi $Abi --android-sdk $AndroidSdk --javac $javac
if ($LASTEXITCODE) { throw 'Cannot begin a consistent APK generation' }
$packages=[Collections.Generic.List[object]]::new()
foreach ($app in $apps) {
    $deployment="$root/deployment/$app"
    $native="$deployment/libs/$Abi/lib${app}_$Abi.so"
    & "$PSScriptRoot/package.ps1" -QtSdk "$root/sdk-packaging" `
        -NativeLibrary $native -RuntimeLibrary "$root/libc++_shared.so" `
        -OutputDirectory "$root/apk" -AndroidSdk $androidSdk `
        -Package ('org.longreachqt.examples.qt6.'+$app.Replace('-','_')) `
        -DeploymentDirectory $deployment -Abi $Abi
    $apk=Get-Item "$root/apk/$app.apk"
    $packages.Add([pscustomobject]@{ app=$app; size=$apk.Length; sha256=(Get-FileHash $apk.FullName).Hash.ToLowerInvariant(); packaged_utc=[DateTime]::UtcNow.ToString('o') })
    $packages | ConvertTo-Json | Set-Content "$root/apk/packages.json"
    Write-Output "Packaged $app ($($apk.Length) bytes)"
}

& python "$repo/scripts/build/android-api21/artifact-manifest.py" record-apks --root $root --qt-major 6 --abi $Abi --android-sdk $AndroidSdk --javac $javac
if ($LASTEXITCODE) { throw 'Cannot bind APKs to the completed example generation' }

} finally { if ($artifactLock) { $artifactLock.Dispose() } }
