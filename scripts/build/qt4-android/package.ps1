# SPDX-License-Identifier: GPL-3.0-or-later

param(
    [Parameter(Mandatory)] [ValidateSet('bootstrap', 'strict', 'core', 'quick', 'selftest', 'graphics', 'network', 'painting')] [string] $Profile,
    [Parameter(Mandatory)] [string] $NativeDirectory,
    [Parameter(Mandatory)] [string] $OutputDirectory,
    [Parameter(Mandatory)] [string] $AndroidSdk,
    [Parameter(Mandatory)] [string] $AndroidJar
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/host.ps1"
$fixtures = (Resolve-Path "$PSScriptRoot/../../../tests/android-donut/java").Path
$java = (Get-Command javac.exe).Source | Split-Path
$tools = Join-Path $AndroidSdk 'build-tools/36.0.0'
$library = (Get-Item -LiteralPath "$NativeDirectory/$Profile.so").FullName
$keyStore = Join-Path $OutputDirectory 'local-probe.jks'
$apk = Join-Path $OutputDirectory "$Profile.apk"
$work = (New-Item -ItemType Directory -Path (Join-Path $OutputDirectory ("package-" + [guid]::NewGuid()))).FullName

$manifest = 'AndroidManifest.xml'
$sources = @("$fixtures/ProbeActivity.java")
if ($Profile -in 'selftest', 'network') {
    $manifest = 'selftest-AndroidManifest.xml'
}
if ($Profile -eq 'quick') {
    $manifest = 'quick-AndroidManifest.xml'
    $sources = @("$fixtures/QuickActivity.java", "$fixtures/QuickCoverActivity.java", "$fixtures/GalleryActivity.java",
        "$fixtures/WidgetsActivity.java", "$fixtures/QuickInstrumentation.java")
}

try {
    New-Item -ItemType Directory -Path "$work/lib/armeabi", "$work/classes" -Force | Out-Null
    Copy-Item -LiteralPath $library -Destination "$work/lib/armeabi/libdonut_probe.so"
    Copy-Item -LiteralPath "$fixtures/$manifest" -Destination "$work/AndroidManifest.xml"

    Invoke-DonutCommand "$java/javac.exe" (@('--release', '8', '-classpath', $AndroidJar, '-d', "$work/classes") + $sources)
    $classes = @(Get-ChildItem -LiteralPath "$work/classes" -Filter '*.class' -File -Recurse |
        Select-Object -ExpandProperty FullName)
    Invoke-DonutCommand "$tools/d8.bat" (@('--min-api', '4', '--lib', $AndroidJar, '--output', $work) + $classes)
    Invoke-DonutCommand "$tools/aapt.exe" @('package', '-M', "$work/AndroidManifest.xml", '-I', $AndroidJar, '-F', "$work/unsigned.apk")

    Push-Location -LiteralPath $work
    try {
        Invoke-DonutCommand "$tools/aapt.exe" @('add', 'unsigned.apk', 'classes.dex', 'lib/armeabi/libdonut_probe.so')
        if (!(Test-Path -LiteralPath $keyStore)) {
            Invoke-DonutCommand "$java/keytool.exe" @('-genkeypair', '-keystore', $keyStore,
                '-storepass', 'donut-probe-local', '-keypass', 'donut-probe-local', '-alias', 'local-probe',
                '-keyalg', 'RSA', '-keysize', '2048', '-dname', 'CN=Local Android Probe', '-validity', '365')
        }
        Invoke-DonutCommand "$tools/zipalign.exe" @('-f', '4', 'unsigned.apk', 'aligned.apk')
        Invoke-DonutCommand "$tools/apksigner.bat" @('sign', '--ks', $keyStore, '--ks-key-alias', 'local-probe',
            '--ks-pass', 'pass:donut-probe-local', '--min-sdk-version', '4', '--v1-signing-enabled', 'true',
            '--v2-signing-enabled', 'false', '--v3-signing-enabled', 'false', '--v4-signing-enabled', 'false',
            '--out', $apk, 'aligned.apk')
        Invoke-DonutCommand "$tools/apksigner.bat" @('verify', '--min-sdk-version', '4', '--verbose', $apk)
        Invoke-DonutCommand "$tools/aapt.exe" @('dump', 'badging', $apk)
    } finally {
        Pop-Location
    }
} finally {
    $resolved = (Resolve-Path -LiteralPath $work).Path
    $outputRoot = (Resolve-Path -LiteralPath $OutputDirectory).Path
    if ([IO.Path]::GetDirectoryName($resolved) -eq $outputRoot) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
