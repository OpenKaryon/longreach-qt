# SPDX-License-Identifier: GPL-3.0-or-later

param(
    [ValidateSet('armeabi', 'x86_64')] [string] $Abi = 'armeabi',
    [Parameter(Mandatory)] [ValidateSet('bootstrap', 'strict', 'core', 'quick', 'selftest', 'graphics', 'network', 'painting', 'widgets', 'multimedia', 'gl', 'qml')] [string] $Profile,
    [Parameter(Mandatory)] [string] $NativeDirectory,
    [Parameter(Mandatory)] [string] $OutputDirectory,
    [Parameter(Mandatory)] [string] $AndroidSdk,
    [Parameter(Mandatory)] [string] $AndroidJar
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/host.ps1"
$OutputDirectory = (New-Item -ItemType Directory -Force -Path $OutputDirectory).FullName
$NativeDirectory = (Resolve-Path -LiteralPath $NativeDirectory).Path
$AndroidJar = (Get-Item -LiteralPath $AndroidJar).FullName
$fixtures = (Resolve-Path "$PSScriptRoot/../../../tests/android-donut/java").Path
$java = (Get-Command javac.exe).Source | Split-Path
$tools = Join-Path $AndroidSdk 'build-tools/36.0.0'
$library = (Get-Item -LiteralPath "$NativeDirectory/$Profile.so").FullName
$keyStore = Join-Path $OutputDirectory 'local-probe.jks'
$apk = Join-Path $OutputDirectory "$Profile.apk"
if (Test-Path -LiteralPath $apk) {
    $previousHash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
    $history = (New-Item -ItemType Directory -Force -Path "$OutputDirectory/apk-history/$previousHash").FullName
    $previousApk = Join-Path $history "$Profile.apk"
    if (!(Test-Path -LiteralPath $previousApk)) { Copy-Item -LiteralPath $apk -Destination $previousApk }
    if ((Get-FileHash -LiteralPath $previousApk -Algorithm SHA256).Hash.ToLowerInvariant() -ne $previousHash) {
        throw 'Previous APK history does not match the package being replaced'
    }
}
$work = (New-Item -ItemType Directory -Path (Join-Path $OutputDirectory ("package-" + [guid]::NewGuid()))).FullName

$minimum = if ($Abi -eq 'armeabi') { '4' } else { '21' }
$manifest = 'AndroidManifest.xml'
$sources = @("$fixtures/ProbeActivity.java")
if ($Profile -in 'selftest', 'network', 'widgets') {
    $manifest = 'selftest-AndroidManifest.xml'
}
if ($Profile -eq 'quick') {
    $manifest = 'quick-AndroidManifest.xml'
    $sources = @("$fixtures/QuickActivity.java", "$fixtures/QuickCoverActivity.java", "$fixtures/GalleryActivity.java",
        "$fixtures/WidgetsActivity.java", "$fixtures/QuickInstrumentation.java")
}

$sources += "$fixtures/NativeLoader.java"

try {
    New-Item -ItemType Directory -Path "$work/lib/$Abi", "$work/classes" -Force | Out-Null
    Copy-Item -LiteralPath $library -Destination "$work/lib/$Abi/libdonut_probe.so"
    Copy-Item -LiteralPath "$fixtures/$manifest" -Destination "$work/AndroidManifest.xml"
    if ($minimum -eq '21') {
        Copy-Item -LiteralPath "$NativeDirectory/libc++_shared.so" -Destination "$work/lib/$Abi/libc++_shared.so"
        $xml = [IO.File]::ReadAllText("$work/AndroidManifest.xml")
        $xml = $xml.Replace('android:minSdkVersion="4" android:targetSdkVersion="4"',
                            'android:minSdkVersion="21" android:targetSdkVersion="21"')
        $xml = $xml.Replace('</application>', '<meta-data android:name="org.longreachqt.sharedRuntime" android:value="true" /></application>')
        [IO.File]::WriteAllText("$work/AndroidManifest.xml", $xml)
    }

    Invoke-DonutCommand "$java/javac.exe" (@('--release', '8', '-classpath', $AndroidJar, '-d', "$work/classes") + $sources)
    $classes = @(Get-ChildItem -LiteralPath "$work/classes" -Filter '*.class' -File -Recurse |
        Select-Object -ExpandProperty FullName)
    Invoke-DonutCommand "$tools/d8.bat" (@('--min-api', $minimum, '--lib', $AndroidJar, '--output', $work) + $classes)
    Invoke-DonutCommand "$tools/aapt.exe" @('package', '-M', "$work/AndroidManifest.xml", '-I', $AndroidJar, '-F', "$work/unsigned.apk")

    Push-Location -LiteralPath $work
    try {
        $members = @('add', 'unsigned.apk', 'classes.dex', "lib/$Abi/libdonut_probe.so")
        if ($minimum -eq '21') { $members += "lib/$Abi/libc++_shared.so" }
        Invoke-DonutCommand "$tools/aapt.exe" $members
        if (!(Test-Path -LiteralPath $keyStore)) {
            Invoke-DonutCommand "$java/keytool.exe" @('-genkeypair', '-keystore', $keyStore,
                '-storepass', 'donut-probe-local', '-keypass', 'donut-probe-local', '-alias', 'local-probe',
                '-keyalg', 'RSA', '-keysize', '2048', '-dname', 'CN=Local Android Probe', '-validity', '365')
        }
        Invoke-DonutCommand "$tools/zipalign.exe" @('-f', '4', 'unsigned.apk', 'aligned.apk')
        Invoke-DonutCommand "$tools/apksigner.bat" @('sign', '--ks', $keyStore, '--ks-key-alias', 'local-probe',
            '--ks-pass', 'pass:donut-probe-local', '--min-sdk-version', $minimum, '--v1-signing-enabled', 'true',
            '--v2-signing-enabled', 'false', '--v3-signing-enabled', 'false', '--v4-signing-enabled', 'false',
            '--out', $apk, 'aligned.apk')
        Invoke-DonutCommand "$tools/apksigner.bat" @('verify', '--min-sdk-version', $minimum, '--verbose', $apk)
        $badging=@(Invoke-DonutCommand "$tools/aapt.exe" @('dump', 'badging', $apk))
        $badging | Set-Content "$apk.badging.txt"
        $badging | Write-Output
        if (!(($badging -join "`n") -match ("(?m)^sdkVersion:'" + $minimum + "'\s*$")) -or
                !(($badging -join "`n") -match ("(?m)^native-code: '" + [regex]::Escape($Abi) + "'\s*$"))) {
            throw 'Packaged APK minimum API or native ABI differs from the selected profile'
        }
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
