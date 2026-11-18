# SPDX-License-Identifier: GPL-3.0-or-later

param([Parameter(Mandatory)][string]$AndroidSdk, [Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path "$PSScriptRoot/../../..").Path
$root=(Resolve-Path -LiteralPath $OutputDirectory).Path
$apps=@(Get-Content "$repo/tests/expected-apps.txt" | Where-Object { $_ -match '^[a-z]' -and $_ -ne 'smoke-runner' })
if ($apps.Count -ne 8) { throw 'Expected eight applications' }
& python "$repo/scripts/build/android-api21/artifact-manifest.py" check-examples --root $root --qt-major 6 --abi armeabi-v7a
if ($LASTEXITCODE) { throw 'Packaging requires a complete, unchanged example generation' }
# A failed replacement must not leave an earlier package generation marked ready.
Remove-Item -LiteralPath "$root/apk-manifest.json" -Force -ErrorAction SilentlyContinue
$packages=[Collections.Generic.List[object]]::new()
foreach ($app in $apps) {
    $deployment="$root/deployment/$app"
    $native="$deployment/libs/armeabi-v7a/lib${app}_armeabi-v7a.so"
    & "$PSScriptRoot/package.ps1" -QtSdk "$root/sdk-packaging" `
        -NativeLibrary $native -RuntimeLibrary "$root/libc++_shared.so" `
        -OutputDirectory "$root/apk" -AndroidSdk $androidSdk `
        -Package ('org.longreachqt.examples.qt6.'+$app.Replace('-','_')) `
        -DeploymentDirectory $deployment
    $apk=Get-Item "$root/apk/$app.apk"
    $packages.Add([pscustomobject]@{ app=$app; size=$apk.Length; sha256=(Get-FileHash $apk.FullName).Hash.ToLowerInvariant(); packaged_utc=[DateTime]::UtcNow.ToString('o') })
    $packages | ConvertTo-Json | Set-Content "$root/apk/packages.json"
    Write-Output "Packaged $app ($($apk.Length) bytes)"
}

& python "$repo/scripts/build/android-api21/artifact-manifest.py" record-apks --root $root --qt-major 6 --abi armeabi-v7a
if ($LASTEXITCODE) { throw 'Cannot bind APKs to the completed example generation' }
