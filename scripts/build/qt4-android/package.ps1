# SPDX-License-Identifier: GPL-3.0-or-later

param(
    [ValidateSet('armeabi', 'x86', 'x86_64', 'arm64-v8a')] [string] $Abi = 'armeabi',
    [Parameter(Mandatory)] [ValidateSet('bootstrap', 'strict', 'core', 'quick', 'selftest', 'graphics', 'network', 'painting', 'widgets', 'multimedia', 'gl', 'qml')] [string] $Profile,
    [Parameter(Mandatory)] [string] $NativeDirectory,
    [Parameter(Mandatory)] [string] $OutputDirectory,
    [Parameter(Mandatory)] [string] $AndroidSdk,
    [Parameter(Mandatory)] [string] $AndroidJar,
    $JavaTools
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/host.ps1"
$OutputDirectory = (New-Item -ItemType Directory -Force -Path $OutputDirectory).FullName
. "$PSScriptRoot/../android-api21/artifact-lock.ps1"
$artifactLock=Enter-AndroidArtifactLock $OutputDirectory
try {
Clear-AndroidResultAggregates $OutputDirectory
$NativeDirectory = (Resolve-Path -LiteralPath $NativeDirectory).Path
$AndroidJar = (Get-Item -LiteralPath $AndroidJar).FullName
$fixtures = (Resolve-Path "$PSScriptRoot/../../../tests/android-donut/java").Path
if (!$JavaTools) { $JavaTools = Get-AndroidPackagingJava }
$tools = Join-Path $AndroidSdk 'build-tools/36.0.0'
$library = (Get-Item -LiteralPath "$NativeDirectory/$Profile.so").FullName
$repo=(Resolve-Path "$PSScriptRoot/../../..").Path
$nativeInputs=@($library)
if ($Abi -ne 'armeabi') { $nativeInputs+="$NativeDirectory/libc++_shared.so" }
Invoke-DonutCommand python (@("$repo/scripts/build/android-api21/native-abi.py",'--abi',$Abi) + $nativeInputs)
$keyStore = Initialize-DonutSigningKey $OutputDirectory (Split-Path $javaTools.javac)
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

$minimum = switch ($Abi) { 'armeabi' { '4' }; 'x86' { '10' }; 'x86_64' { '21' }; 'arm64-v8a' { '21' } }
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
    if ($minimum -ne '4') {
        Copy-Item -LiteralPath "$NativeDirectory/libc++_shared.so" -Destination "$work/lib/$Abi/libc++_shared.so"
        $xml = [IO.File]::ReadAllText("$work/AndroidManifest.xml")
        $xml = $xml.Replace('android:minSdkVersion="4" android:targetSdkVersion="4"',
                            ('android:minSdkVersion="' + $minimum + '" android:targetSdkVersion="' + $minimum + '"'))
        $xml = $xml.Replace('</application>', '<meta-data android:name="org.longreachqt.sharedRuntime" android:value="true" /></application>')
        [IO.File]::WriteAllText("$work/AndroidManifest.xml", $xml)
    }

    Invoke-DonutCommand $javaTools.javac (@('--release', '8', '-classpath', $AndroidJar, '-d', "$work/classes") + $sources)
    $classes = @(Get-ChildItem -LiteralPath "$work/classes" -Filter '*.class' -File -Recurse |
        Select-Object -ExpandProperty FullName)
    Invoke-DonutCommand "$tools/d8.bat" (@('--min-api', $minimum, '--lib', $AndroidJar, '--output', $work) + $classes)
    Invoke-DonutCommand "$tools/aapt.exe" @('package', '-M', "$work/AndroidManifest.xml", '-I', $AndroidJar, '-F', "$work/unsigned.apk")

    Push-Location -LiteralPath $work
    try {
        $members = @('add', 'unsigned.apk', 'classes.dex', "lib/$Abi/libdonut_probe.so")
        if ($minimum -ne '4') { $members += "lib/$Abi/libc++_shared.so" }
        Invoke-DonutCommand "$tools/aapt.exe" $members
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

} finally { if ($artifactLock) { $artifactLock.Dispose() } }
