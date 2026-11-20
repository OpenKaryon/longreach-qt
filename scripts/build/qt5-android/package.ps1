# SPDX-License-Identifier: GPL-3.0-or-later

param(
    [ValidateSet('armeabi-v7a','arm64-v8a')][string] $Abi = 'armeabi-v7a',
    [Parameter(Mandatory)] [string] $QtSdk,
    [Parameter(Mandatory)] [string] $NativeLibrary,
    [Parameter(Mandatory)] [string] $RuntimeLibrary,
    [Parameter(Mandatory)] [string] $OutputDirectory,
    [Parameter(Mandatory)] [string] $AndroidSdk,
    [string] $CompileApi = '35',
    [string[]] $Modules = @('Core', 'Gui', 'Widgets'),
    [string[]] $Plugins,
    [string] $Package = 'org.longreachqt.examples.probe',
    [string] $DeploymentDirectory
)

$ErrorActionPreference = 'Stop'
$minimumApi = if ($Abi -eq 'armeabi-v7a') { '10' } else { '21' }
if (!$PSBoundParameters.ContainsKey('Plugins')) { $Plugins = @("platforms/libplugins_platforms_qtforandroid_$Abi.so") }
function Invoke-AndroidTool([string] $Program, [string[]] $Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program exited with code $LASTEXITCODE." }
}
$QtSdk = (Resolve-Path -LiteralPath $QtSdk).Path
$NativeLibrary = (Get-Item -LiteralPath $NativeLibrary).FullName
$RuntimeLibrary = (Get-Item -LiteralPath $RuntimeLibrary).FullName
$OutputDirectory = (New-Item -ItemType Directory -Path $OutputDirectory -Force).FullName
$tools = Join-Path $AndroidSdk 'build-tools/36.0.0'
$androidJar = Join-Path $AndroidSdk "platforms/android-$CompileApi/android.jar"
$java = Split-Path (Get-Command javac.exe).Source
$work = (New-Item -ItemType Directory -Path (Join-Path $OutputDirectory ("package-" + [guid]::NewGuid()))).FullName
$keyStore = Join-Path $OutputDirectory 'local-examples.jks'
$appName = [IO.Path]::GetFileNameWithoutExtension($NativeLibrary)
if (!$appName.StartsWith('lib') -or !$appName.EndsWith("_$Abi")) {
    throw "Expected lib<application>_$Abi.so."
}
$appName = $appName.Substring(3, $appName.Length - 3 - ("_$Abi").Length)
$apk = Join-Path $OutputDirectory "$appName.apk"
if (Test-Path -LiteralPath $apk) {
    if ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($apk)) -ne $OutputDirectory) {
        throw 'Unexpected APK output path'
    }
    $previous=(New-Item -ItemType Directory -Path "$OutputDirectory/previous" -Force).FullName
    Move-Item -LiteralPath $apk -Destination (Join-Path $previous ("$appName-"+[guid]::NewGuid()+'.apk'))
}

try {
    New-Item -ItemType Directory -Force -Path "$work/lib/$Abi", "$work/classes", "$work/generated", "$work/res/values" | Out-Null
    Get-ChildItem -LiteralPath "$QtSdk/src/android/java/res" | Copy-Item -Destination "$work/res" -Recurse -Force
    if ($DeploymentDirectory) {
        $DeploymentDirectory = (Resolve-Path -LiteralPath $DeploymentDirectory).Path
        Get-ChildItem -LiteralPath "$DeploymentDirectory/libs/$Abi" -Filter '*.so' -File |
            Copy-Item -Destination "$work/lib/$Abi" -Force
        Get-ChildItem -LiteralPath "$DeploymentDirectory/res" |
            Copy-Item -Destination "$work/res" -Recurse -Force
        if (Test-Path -LiteralPath "$DeploymentDirectory/assets") {
            New-Item -ItemType Directory -Path "$work/assets" | Out-Null
            Get-ChildItem -LiteralPath "$DeploymentDirectory/assets" |
                Copy-Item -Destination "$work/assets" -Recurse -Force
        }
    } else {
        $qtEntries = @("<item>$Abi;c++_shared</item>")
        foreach ($module in $Modules) {
            Copy-Item -LiteralPath "$QtSdk/lib/libQt5${module}_$Abi.so" -Destination "$work/lib/$Abi"
            $qtEntries += "<item>$Abi;Qt5${module}_$Abi</item>"
        }
        $localEntries = @()
        foreach ($plugin in $Plugins) {
            $pluginName = Split-Path $plugin -Leaf
            Copy-Item -LiteralPath "$QtSdk/plugins/$plugin" -Destination "$work/lib/$Abi"
            $localEntries += "<item>$Abi;$pluginName</item>"
        }
        $libs = @"
    <resources>
        <array name="qt_libs">$($qtEntries -join '')</array>
        <array name="bundled_libs" />
        <array name="load_local_libs">$($localEntries -join '')</array>
    </resources>
"@
        [IO.File]::WriteAllText("$work/res/values/libs.xml", $libs)
    }
    # Explicit native/runtime inputs take precedence over deployment copies.
    Copy-Item -LiteralPath $NativeLibrary, $RuntimeLibrary -Destination "$work/lib/$Abi" -Force
    $permissions = @('android.permission.INTERNET')
    $moduleInitialization = ''
    if ($DeploymentDirectory -and (Test-Path -LiteralPath "$DeploymentDirectory/AndroidManifest.xml")) {
        [xml] $deployedManifest = Get-Content -LiteralPath "$DeploymentDirectory/AndroidManifest.xml" -Raw
        # Qt modules use this metadata to receive their Android Context before
        # native code starts (Bluetooth, Positioning, Multimedia and NFC).
        foreach ($entry in $deployedManifest.manifest.application.activity.'meta-data') {
            if ($entry -and $entry.GetAttribute('name', 'http://schemas.android.com/apk/res/android') -eq
                    'android.app.static_init_classes') {
                $classes = $entry.GetAttribute('value', 'http://schemas.android.com/apk/res/android')
                $moduleInitialization = '<meta-data android:name="android.app.static_init_classes" android:value="' +
                    [Security.SecurityElement]::Escape($classes) + '"/>'
            }
        }
        foreach ($entry in $deployedManifest.manifest.'uses-permission') {
            if ($entry) {
                $permissions += $entry.GetAttribute('name', 'http://schemas.android.com/apk/res/android')
            }
        }
    }
    $permissionEntries = @($permissions | Where-Object { $_ } | Sort-Object -Unique | ForEach-Object {
        '<uses-permission android:name="' + [Security.SecurityElement]::Escape($_) + '"/>'
    })
    $manifest = @"
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="$Package" android:versionCode="1" android:versionName="1.0">
    <uses-sdk android:minSdkVersion="$minimumApi" android:targetSdkVersion="$minimumApi"/>
    $($permissionEntries -join [Environment]::NewLine)
    <application android:name="org.qtproject.qt5.android.bindings.QtApplication"
        android:label="$appName" android:debuggable="true">
        <activity android:name="org.longreachqt.examples.SmokeActivity" android:exported="true"
            android:configChanges="orientation|keyboard|keyboardHidden|screenLayout|uiMode"
            android:screenOrientation="landscape">
            <intent-filter><action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/></intent-filter>
            <meta-data android:name="android.app.lib_name" android:value="$appName"/>
            <meta-data android:name="android.app.qt_libs_resource_id" android:resource="@array/qt_libs"/>
            <meta-data android:name="android.app.bundled_libs_resource_id" android:resource="@array/bundled_libs"/>
            <meta-data android:name="android.app.load_local_libs_resource_id" android:resource="@array/load_local_libs"/>
            <meta-data android:name="android.app.use_local_qt_libs" android:value="1"/>
            <meta-data android:name="android.app.bundle_local_qt_libs" android:value="1"/>
            $moduleInitialization
            <meta-data android:name="android.app.extract_android_style" android:value="none"/>
        </activity>
    </application>
</manifest>
"@
    [IO.File]::WriteAllText("$work/AndroidManifest.xml", $manifest)
    $javaSources = @("$PSScriptRoot/../../../tests/android/java/SmokeActivity.java")
    $javaSources += @(Get-ChildItem "$QtSdk/src/android/java/src" -Recurse -Filter '*.java' -File | Select-Object -ExpandProperty FullName)
    $aidlRoot = (Resolve-Path -LiteralPath "$QtSdk/src/android/java/src").Path
    foreach ($aidl in Get-ChildItem $aidlRoot -Recurse -Filter '*.aidl' -File) {
        Invoke-AndroidTool "$tools/aidl.exe" @("-p$AndroidSdk/platforms/android-$CompileApi/framework.aidl", "-I$aidlRoot", "-o$work/generated", $aidl.FullName)
    }
    $javaSources += @(Get-ChildItem "$work/generated" -Recurse -Filter '*.java' -File | Select-Object -ExpandProperty FullName)
    $jarDirectory = if ($DeploymentDirectory) { "$DeploymentDirectory/libs" } else { "$QtSdk/jar" }
    $jars = @(Get-ChildItem $jarDirectory -Filter '*.jar' -File | Select-Object -ExpandProperty FullName)
    $classpath = (@($androidJar) + $jars) -join ';'
    Invoke-AndroidTool "$java/javac.exe" (@('--release', '8', '-classpath', $classpath, '-d', "$work/classes") + $javaSources)
    $classes = @(Get-ChildItem "$work/classes" -Recurse -Filter '*.class' -File | Select-Object -ExpandProperty FullName)
    Invoke-AndroidTool "$tools/d8.bat" (@('--min-api', $minimumApi, '--lib', $androidJar, '--output', $work) + $jars + $classes)
    $aaptArguments = @('package', '-M', "$work/AndroidManifest.xml", '-I', $androidJar,
        '-S', "$work/res", '-F', "$work/unsigned.apk")
    if (Test-Path -LiteralPath "$work/assets") { $aaptArguments += @('-A', "$work/assets") }
    Invoke-AndroidTool "$tools/aapt.exe" $aaptArguments
    Push-Location -LiteralPath $work
    try {
        $nativeFiles = @(Get-ChildItem "lib/$Abi" -File | ForEach-Object { "lib/$Abi/$($_.Name)" })
        Invoke-AndroidTool "$tools/aapt.exe" (@('add', 'unsigned.apk', 'classes.dex') + $nativeFiles)
        if (!(Test-Path -LiteralPath $keyStore)) {
            Invoke-AndroidTool "$java/keytool.exe" @('-genkeypair', '-keystore', $keyStore,
                '-storepass', 'longreach-local', '-keypass', 'longreach-local', '-alias', 'examples',
                '-keyalg', 'RSA', '-keysize', '2048', '-dname', 'CN=Local Longreach Examples', '-validity', '365')
        }
        Invoke-AndroidTool "$tools/zipalign.exe" @('-f', '4', 'unsigned.apk', 'aligned.apk')
        Invoke-AndroidTool "$tools/apksigner.bat" @('sign', '--ks', $keyStore, '--ks-key-alias', 'examples',
            '--ks-pass', 'pass:longreach-local', '--min-sdk-version', $minimumApi, '--v1-signing-enabled', 'true',
            '--v2-signing-enabled', 'false', '--v3-signing-enabled', 'false', '--v4-signing-enabled', 'false',
            '--out', $apk, 'aligned.apk')
        Invoke-AndroidTool "$tools/apksigner.bat" @('verify', '--min-sdk-version', $minimumApi, $apk)
        Invoke-AndroidTool "$tools/aapt.exe" @('dump', 'badging', $apk)
    } finally {
        Pop-Location
    }
} finally {
    $resolved = (Resolve-Path -LiteralPath $work).Path
    if ([IO.Path]::GetDirectoryName($resolved) -eq $OutputDirectory) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
