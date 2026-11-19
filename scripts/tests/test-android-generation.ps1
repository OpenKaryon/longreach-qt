# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
<# Exercise the actual Qt6 wrapper and integrity helper across a failed Docker run. #>
param([string]$RepoRoot=(Resolve-Path "$PSScriptRoot/../..").Path)
$ErrorActionPreference='Stop'
$parent=(New-Item -ItemType Directory -Force "$RepoRoot/build/fixtures").FullName
$fixture=Join-Path $parent ('android-generation-'+[guid]::NewGuid())
$global:AndroidGenerationRunAttempted=$false
$global:AndroidGenerationPackageAttempted=$false
function Get-Process { param($Name,$ErrorAction) return $null }
function docker {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    $global:LASTEXITCODE=0
    if($Arguments[0] -eq 'image') {
        return (@{Id='sha256:'+('a'*64);Os='linux';Architecture='amd64';Config=@{Labels=@{
            'org.openkaryon.longreach-qt.platform'='android-lollipop-armeabi-v7a'
            'org.openkaryon.longreach-qt.android-api'='21'
            'org.openkaryon.longreach-qt.version'='6.8.5'
            'org.openkaryon.longreach-qt.compiler'='LLVM 21.1.8'
        }}} | ConvertTo-Json -Depth 5 -Compress)
    }
    if($Arguments[0] -eq 'run') {
        $global:AndroidGenerationRunAttempted=$true
        # Model a native build failing after overwriting its first deployment.
        [IO.File]::WriteAllText("$fixture/output/deployment/qt-selftest/libs/armeabi-v7a/libqt-selftest_armeabi-v7a.so",'new partial library')
        $global:LASTEXITCODE=1
        return
    }
    throw 'Unexpected Docker work'
}
try {
    foreach($relative in @('scripts/build/qt6-android.ps1','scripts/build/qt6-android/package-suite.ps1',
            'scripts/build/android-api21/artifact-manifest.py','tests/expected-apps.txt')) {
        $destination=Join-Path $fixture $relative
        New-Item -ItemType Directory -Force (Split-Path $destination) | Out-Null
        Copy-Item -LiteralPath (Join-Path $RepoRoot $relative) -Destination $destination
    }
    New-Item -ItemType Directory -Force "$fixture/sdk","$fixture/output/apk", "$fixture/output/sdk-packaging/src/android/java/src",
        "$fixture/output/sdk-packaging/src/android/java/res","$fixture/output/sdk-packaging/jar" | Out-Null
    [IO.File]::WriteAllText("$fixture/output/sdk-packaging/jar/Qt6Android.jar",'old jar')
    [IO.File]::WriteAllText("$fixture/output/libc++_shared.so",'old runtime')
    foreach($name in @('examples-manifest.json','apk-manifest.json')) {
        [IO.File]::WriteAllText("$fixture/output/$name",'{"previous":"successful generation"}')
    }
    foreach($app in @(Get-Content "$fixture/tests/expected-apps.txt" | Where-Object {$_ -match '^[a-z]' -and $_ -ne 'smoke-runner'})) {
        $directory="$fixture/output/deployment/$app"
        New-Item -ItemType Directory -Force "$directory/libs/armeabi-v7a","$directory/res/values" | Out-Null
        [IO.File]::WriteAllText("$directory/libs/armeabi-v7a/lib${app}_armeabi-v7a.so",'old library')
        [IO.File]::WriteAllText("$directory/res/values/libs.xml",'<resources/>')
        [IO.File]::WriteAllText("$fixture/output/apk/$app.apk",'previous APK')
    }
    try { & "$fixture/scripts/build/qt6-android.ps1" -Mode examples -OutputDirectory "$fixture/output"; throw 'Expected compilation failure' }
    catch { if($_.Exception.Message -notmatch 'docker exited with code 1') {throw} }
    if(!$global:AndroidGenerationRunAttempted -or !(Test-Path "$fixture/output/examples-in-progress.json") -or
            (Test-Path "$fixture/output/examples-manifest.json") -or (Test-Path "$fixture/output/apk-manifest.json")) {
        throw 'Failed build left an apparently complete generation'
    }
    try { & "$fixture/scripts/build/qt6-android.ps1" -Mode package -AndroidSdk "$fixture/sdk" -OutputDirectory "$fixture/output"; throw 'Expected package refusal' }
    catch { if($_.Exception.Message -notmatch 'complete, unchanged example generation') {throw} }
    if((Get-Content "$fixture/output/apk/qt-selftest.apk" -Raw) -ne 'previous APK') {throw 'Previous APK was replaced'}
    $global:LASTEXITCODE=0
    Write-Output 'PASS: actual wrapper invalidates completion before Docker; a failed build preserves old APKs and blocks mixed packaging'
} finally {
    if(Test-Path -LiteralPath $fixture) {
        $resolved=(Resolve-Path -LiteralPath $fixture).Path
        if([IO.Path]::GetDirectoryName($resolved) -ne $parent) {throw 'Unexpected fixture cleanup path'}
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
