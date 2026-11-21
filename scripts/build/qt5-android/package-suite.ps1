# SPDX-License-Identifier: GPL-3.0-or-later
param([ValidateSet('armeabi-v7a','arm64-v8a','x86','x86_64')][string]$Abi='armeabi-v7a',
      [Parameter(Mandatory)][string]$AndroidSdk, [Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path "$PSScriptRoot/../../..").Path
$root=(Resolve-Path -LiteralPath $OutputDirectory).Path
$apps=@(Get-Content "$repo/tests/expected-apps.txt" | Where-Object { $_ -match '^[a-z]' -and $_ -ne 'smoke-runner' })
if ($apps.Count -ne 8) { throw 'Expected eight shared applications' }
$deployments=@($apps | ForEach-Object { @{App=$_; Directory="deployment/$_"; ApkDirectory='apk'} })
$deployments+=@{App='qt-selftest'; Directory='deployment-extended/qt-selftest'; ApkDirectory='apk/extended'}
foreach ($relative in @('sdk/src/android/java/src','sdk/src/android/java/res','native/libc++_shared.so')) {
    if (!(Test-Path -LiteralPath "$root/$relative")) { throw "Missing packaging input: $relative. Run examples mode first." }
}
if (!(Get-ChildItem "$root/sdk/jar" -Filter '*.jar' -File -ErrorAction SilentlyContinue)) { throw 'Missing SDK Java JARs' }
foreach ($item in $deployments) {
    foreach ($relative in @("libs/$Abi/lib$($item.App)_$Abi.so",'res/values/libs.xml')) {
        if (!(Test-Path -LiteralPath "$root/$($item.Directory)/$relative")) { throw "Missing deployment: $($item.Directory)/$relative" }
    }
}
& python "$repo/scripts/build/android-api21/artifact-manifest.py" check-examples --root $root --qt-major 5 --abi $Abi
if ($LASTEXITCODE) { throw 'Packaging requires a complete, unchanged example generation' }
# A failed replacement must not leave an earlier package generation marked ready.
Remove-Item -LiteralPath "$root/apk-manifest.json" -Force -ErrorAction SilentlyContinue
$packages=[Collections.Generic.List[object]]::new()
foreach ($item in $deployments) {
    $app=$item.App
    $deployment="$root/$($item.Directory)"
    & "$PSScriptRoot/package.ps1" -Abi $Abi -QtSdk "$root/sdk" -AndroidSdk $AndroidSdk `
        -NativeLibrary "$deployment/libs/$Abi/lib${app}_$Abi.so" -RuntimeLibrary "$root/native/libc++_shared.so" `
        -DeploymentDirectory $deployment -OutputDirectory "$root/$($item.ApkDirectory)" `
        -Package ('org.longreachqt.examples.'+$app.Replace('-',''))
    $apk=Get-Item "$root/$($item.ApkDirectory)/$app.apk"
    $packages.Add([pscustomobject]@{ app=$app; apk="$($item.ApkDirectory)/$app.apk"; abi=$Abi; size=$apk.Length; sha256=(Get-FileHash $apk.FullName).Hash.ToLowerInvariant(); packaged_utc=[DateTime]::UtcNow.ToString('o') })
    $packages | ConvertTo-Json | Set-Content "$root/apk/packages.json"
    Write-Output "Packaged $($item.ApkDirectory)/$app.apk ($($apk.Length) bytes)"
}

& python "$repo/scripts/build/android-api21/artifact-manifest.py" record-apks --root $root --qt-major 5 --abi $Abi
if ($LASTEXITCODE) { throw 'Cannot bind APKs to the completed example generation' }
