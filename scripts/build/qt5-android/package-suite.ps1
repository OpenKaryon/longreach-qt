# SPDX-License-Identifier: GPL-3.0-or-later
param([ValidateSet('armeabi-v7a','arm64-v8a','x86','x86_64')][string]$Abi='armeabi-v7a',
      [Parameter(Mandatory)][string]$AndroidSdk, [Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path "$PSScriptRoot/../../..").Path
$root=(Resolve-Path -LiteralPath $OutputDirectory).Path
 . "$repo/scripts/build/android-api21/artifact-lock.ps1"
$artifactLock=Enter-AndroidArtifactLock $root
try {
Clear-AndroidResultAggregates $root
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
& python "$repo/scripts/build/android-api21/artifact-manifest.py" check-examples --root $root --qt-major 5 --abi $Abi --artifact-lease-held
if ($LASTEXITCODE) { throw 'Packaging requires a complete, unchanged example generation' }
if ($Abi -in @('armeabi-v7a','x86')) {
    & python "$repo/scripts/build/android-api21/check-api10-api21-symbols.py" deployments --root $root --abi $Abi
    if ($LASTEXITCODE) { throw 'API10 native deployments are not compatible with API21 symbol availability' }
}

. "$repo/scripts/build/android-api21/packaging-host.ps1"
$javaTools=Get-AndroidPackagingJava
$javac=$javaTools.launcher
Initialize-AndroidExamplesKey "$root/apk" $javaTools | Out-Null
Initialize-AndroidExamplesKey "$root/apk/extended" $javaTools | Out-Null
& python "$repo/scripts/build/android-api21/artifact-manifest.py" begin-apks --root $root --qt-major 5 --abi $Abi --android-sdk $AndroidSdk --javac $javac --artifact-lease-held
if ($LASTEXITCODE) { throw 'Cannot begin a consistent APK generation' }
$packages=[Collections.Generic.List[object]]::new()
foreach ($item in $deployments) {
    $app=$item.App
    $deployment="$root/$($item.Directory)"
    $pluginOptions=@{}
    if ($Abi -in @('armeabi-v7a','x86') -and $app -eq 'quick-qml-gallery') {
        # Bionic API10 has only 96 DSO slots. PNG is built in; the shared
        # gallery uses GIF/JPEG/SVG, not the remaining desktop image handlers.
        $pluginOptions.ImageFormats=@('gif','jpeg','svg')
    }
    & "$PSScriptRoot/package.ps1" @pluginOptions -Abi $Abi -QtSdk "$root/sdk" -AndroidSdk $AndroidSdk `
        -NativeLibrary "$deployment/libs/$Abi/lib${app}_$Abi.so" -RuntimeLibrary "$root/native/libc++_shared.so" `
        -DeploymentDirectory $deployment -OutputDirectory "$root/$($item.ApkDirectory)" `
        -Package ('org.longreachqt.examples.'+$app.Replace('-','')) -JavaTools $javaTools
    $apk=Get-Item "$root/$($item.ApkDirectory)/$app.apk"
    $packages.Add([pscustomobject]@{ app=$app; apk="$($item.ApkDirectory)/$app.apk"; abi=$Abi; size=$apk.Length; sha256=(Get-FileHash $apk.FullName).Hash.ToLowerInvariant(); packaged_utc=[DateTime]::UtcNow.ToString('o') })
    $packages | ConvertTo-Json | Set-Content "$root/apk/packages.json"
    Write-Output "Packaged $($item.ApkDirectory)/$app.apk ($($apk.Length) bytes)"
}

& python "$repo/scripts/build/android-api21/artifact-manifest.py" record-apks --root $root --qt-major 5 --abi $Abi --android-sdk $AndroidSdk --javac $javac --artifact-lease-held
if ($LASTEXITCODE) { throw 'Cannot bind APKs to the completed example generation' }

} finally { if ($artifactLock) { $artifactLock.Dispose() } }
