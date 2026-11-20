# SPDX-License-Identifier: GPL-3.0-or-later
<# Phase routing with recording tools; no native builds, downloads or guests. #>
param([string]$RepoRoot=(Resolve-Path "$PSScriptRoot/../..").Path)
$ErrorActionPreference='Stop'
$temporaryRoot=[IO.Path]::GetTempPath().TrimEnd('\','/')
$fixture=Join-Path $temporaryRoot ('longreach-qt5-modes-'+[guid]::NewGuid())
$previousLog=$env:LONGREACH_MODE_TEST_LOG
$global:Qt5ModeAbi='armeabi-v7a'
$global:Qt5ModeMissing=$false
$global:Qt5ModeId='sha256:'+('a'*64)
function Assert-Mode([bool]$Condition,[string]$Message) { if (!$Condition) { throw $Message } }
function Calls { @(Get-Content -LiteralPath $env:LONGREACH_MODE_TEST_LOG) }
function Reset-Calls { [IO.File]::WriteAllText($env:LONGREACH_MODE_TEST_LOG,'') }
function Get-Process { param($Name,$ErrorAction) return $null }
function docker {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    Add-Content $env:LONGREACH_MODE_TEST_LOG ('docker|'+($Arguments -join '|'))
    $global:LASTEXITCODE=0
    if ($Arguments[0] -eq 'image' -and $Arguments[1] -eq 'inspect') {
        if ($global:Qt5ModeMissing) { $global:LASTEXITCODE=1; return }
        if ($Arguments -contains '{{json .}}') {
            $api=if ($global:Qt5ModeAbi -eq 'armeabi-v7a') { '10' } else { '21' }
            $profile=if ($api -eq '10') { 'gingerbread' } else { 'lollipop' }
            return (@{Id=$global:Qt5ModeId;Os='linux';Architecture='amd64';Config=@{Labels=@{
                'org.openkaryon.longreach-qt.platform'="android-$profile-$global:Qt5ModeAbi"
                'org.openkaryon.longreach-qt.android-api'=$api
                'org.openkaryon.longreach-qt.version'='5.15.19'
                'org.openkaryon.longreach-qt.compiler'='LLVM 21.1.8'
            }}} | ConvertTo-Json -Depth 5 -Compress)
        }
        return $global:Qt5ModeId
    }
    if ($Arguments[0] -eq 'create') { return ('b'*64) }
    if ($Arguments[0] -eq 'cp') {
        $destination=$Arguments[2]
        if ($Arguments[1] -like '*:/opt/qt5-android-*') {
            foreach ($path in @('jar','src/android/java/src','src/android/java/res')) { New-Item -ItemType Directory -Force "$destination/$path" | Out-Null }
            [IO.File]::WriteAllText("$destination/jar/QtAndroid.jar",'fixture')
        } elseif ($Arguments[1] -like '*libc++_shared.so') {
            [IO.File]::WriteAllText($destination,'runtime')
        }
    }
}
# File-integrity behavior is exercised by test_android_artifacts.py.
function python {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    if ($Arguments[0] -notlike '*artifact-manifest.py') { throw 'Unexpected Python work in routing fixture' }
    $global:LASTEXITCODE=0
}
function Invoke-Mode([hashtable]$Options) { & "$fixture/scripts/build/qt5-android.ps1" @Options | Out-Null }
function Expect-Failure([hashtable]$Options,[string]$Message) {
    try { Invoke-Mode $Options } catch { Assert-Mode ($_.Exception.Message -match $Message) "Unexpected error: $_"; return }
    throw 'Expected mode failure'
}
try {
    New-Item -ItemType Directory $fixture | Out-Null
    $env:LONGREACH_MODE_TEST_LOG="$fixture/calls.log"
    foreach ($relative in @('scripts/build/qt5-android.ps1','scripts/build/qt5-android/package-suite.ps1','tests/expected-apps.txt')) {
        $destination=Join-Path $fixture $relative
        New-Item -ItemType Directory -Force (Split-Path $destination) | Out-Null
        Copy-Item -LiteralPath (Join-Path $RepoRoot $relative) -Destination $destination
    }
    New-Item -ItemType Directory -Force "$fixture/scripts/run","$fixture/scripts/fetch","$fixture/android-sdk" | Out-Null
    @'
param($Abi,$Scope,$AndroidSdk)
Add-Content $env:LONGREACH_MODE_TEST_LOG "fetch|$Abi|$Scope"
'@ | Set-Content "$fixture/scripts/fetch/qt5-android.ps1"
    @'
param($Abi,$RunName,$AndroidSdk,$OutputDirectory,$Gpu,$CaseNames,[switch]$DebugQtPlugins,$QtQuickBackend)
Add-Content $env:LONGREACH_MODE_TEST_LOG "test|$Abi|$RunName|$($CaseNames -join ',')|$DebugQtPlugins"
'@ | Set-Content "$fixture/scripts/run/qt5-android-suite.ps1"
    @'
param($Abi,$QtSdk,$AndroidSdk,$NativeLibrary,$RuntimeLibrary,$DeploymentDirectory,$OutputDirectory,$Package)
$app=([IO.Path]::GetFileName($NativeLibrary) -replace '^lib','' -replace ('_'+[regex]::Escape($Abi)+'\.so$'),'')
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
[IO.File]::WriteAllText("$OutputDirectory/$app.apk",$Package)
Add-Content $env:LONGREACH_MODE_TEST_LOG "package|$Abi|$app"
'@ | Set-Content "$fixture/scripts/build/qt5-android/package.ps1"
    $output="$fixture/output with spaces"
    $entry=@{AndroidSdk="$fixture/android-sdk";OutputDirectory=$output}
    Reset-Calls
    Invoke-Mode $entry
    Assert-Mode (@((Calls) | Where-Object { $_ -like 'docker|run|*' }).Count -eq 1) 'Examples did not reuse one ready image'
    Assert-Mode (@((Calls) | Where-Object { $_ -like 'docker|build|*' -or $_ -like 'fetch|*' -or $_ -like 'package|*' }).Count -eq 0) 'Examples entered another phase'
    Assert-Mode ((Get-Content "$output/examples-sdk-image-id.txt") -eq $global:Qt5ModeId) 'Example SDK ID missing'
    $global:Qt5ModeMissing=$true
    Reset-Calls
    Expect-Failure $entry 'Build it explicitly with -Mode sdk'
    Assert-Mode (@(Calls).Count -eq 1) 'Missing SDK triggered more work'
    $global:Qt5ModeMissing=$false
    Reset-Calls
    Expect-Failure ($entry+@{Abi='arm64-v8a'}) 'not the Qt5'
    Assert-Mode (@(Calls).Count -eq 1) 'Wrong ABI entered another phase'
    $global:Qt5ModeAbi='arm64-v8a'
    Reset-Calls
    Invoke-Mode ($entry+@{Mode='examples';Abi='arm64-v8a'})
    Assert-Mode (@(Calls)[0] -like '*longreach-qt5-android-lollipop-arm64-v8a:llvm21') 'Wrong ARM64 default tag'
    Reset-Calls
    Expect-Failure ($entry+@{Mode='examples';Abi='x86_64'}) 'not the Qt5'
    Assert-Mode (@(Calls).Count -eq 1) 'x86_64 consumed an ARM64 SDK'
    $global:Qt5ModeAbi='x86_64'
    Reset-Calls
    Invoke-Mode ($entry+@{Mode='examples';Abi='x86_64'})
    Assert-Mode (@(Calls)[0] -like '*longreach-qt5-android-lollipop-x86_64:llvm21') 'Wrong x86_64 default tag'
    Reset-Calls
    Invoke-Mode ($entry+@{Mode='sdk';Abi='x86_64'})
    Assert-Mode (@((Calls) | Where-Object { $_ -like 'docker|build|*' }).Count -eq 2) 'x86_64 SDK mode did not build once'
    Assert-Mode (@((Calls) | Where-Object { $_ -eq 'fetch|x86_64|sdk' }).Count -eq 1) 'Wrong x86_64 SDK fetch scope'
    Reset-Calls
    Invoke-Mode ($entry+@{Mode='sdk';Abi='arm64-v8a'})
    Assert-Mode (@((Calls) | Where-Object { $_ -like 'docker|build|*' }).Count -eq 2) 'SDK mode did not build once'
    Assert-Mode (@((Calls) | Where-Object { $_ -like 'docker|run|*' -or $_ -like 'docker|create|*' -or $_ -like 'package|*' }).Count -eq 0) 'SDK mode entered examples'
    Assert-Mode (@((Calls) | Where-Object { $_ -eq 'fetch|arm64-v8a|sdk' }).Count -eq 1) 'Wrong SDK fetch scope'
    Reset-Calls
    Invoke-Mode ($entry+@{SdkOnly=$true;Abi='arm64-v8a'})
    Assert-Mode (@((Calls) | Where-Object { $_ -like 'docker|build|*' }).Count -eq 2) 'Legacy SdkOnly alias broke'
    Reset-Calls
    Expect-Failure ($entry+@{Mode='package';SdkOnly=$true}) 'cannot be combined'
    Assert-Mode (@(Calls).Count -eq 0) 'Conflicting modes started work'
    $apps=@(Get-Content "$fixture/tests/expected-apps.txt" | Where-Object { $_ -match '^[a-z]' -and $_ -ne 'smoke-runner' })
    foreach ($abi in @('armeabi-v7a','arm64-v8a','x86_64')) {
        foreach ($directory in (@($apps | ForEach-Object { "deployment/$_" })+'deployment-extended/qt-selftest')) {
            $app=Split-Path $directory -Leaf
            New-Item -ItemType Directory -Force "$output/$directory/libs/$abi","$output/$directory/res/values" | Out-Null
            [IO.File]::WriteAllText("$output/$directory/libs/$abi/lib${app}_$abi.so",'fixture')
            [IO.File]::WriteAllText("$output/$directory/res/values/libs.xml",'<resources/>')
        }
        Reset-Calls
        Invoke-Mode ($entry+@{Mode='package';Abi=$abi})
        Assert-Mode (@(Calls).Count -eq 9 -and @((Calls) | Where-Object { $_ -notlike "package|$abi|*" }).Count -eq 0) 'Packaging lost phase isolation or extended profile'
        Assert-Mode (@(Get-Content "$output/apk/packages.json" -Raw | ConvertFrom-Json).Count -eq 9) 'Incomplete package manifest'
    }
    Remove-Item -LiteralPath "$output/deployment-extended/qt-selftest/libs/arm64-v8a/libqt-selftest_arm64-v8a.so"
    Reset-Calls
    Expect-Failure ($entry+@{Mode='package';Abi='arm64-v8a'}) 'Missing deployment'
    Assert-Mode (@(Calls).Count -eq 0) 'Packaging began without all nine deployments'
    Reset-Calls
    Invoke-Mode ($entry+@{Mode='test';Abi='arm64-v8a';RunName='routing-check';CaseNames=@('strict-cxx23-extended');DebugQtPlugins=$true})
    Assert-Mode (@(Calls).Count -eq 1 -and @(Calls)[0] -eq 'test|arm64-v8a|routing-check|strict-cxx23-extended|True') 'Test mode dropped options or entered another phase'
    Reset-Calls
    Invoke-Mode ($entry+@{Mode='test';Abi='x86_64';RunName='x86-64-routing';CaseNames=@('strict-cxx23-extended')})
    Assert-Mode (@(Calls).Count -eq 1 -and @(Calls)[0] -eq 'test|x86_64|x86-64-routing|strict-cxx23-extended|False') 'x86_64 test mode lost ABI or extended-case routing'
    Write-Output 'PASS: Qt5 ready-image reuse, independent modes, ABI checks, nine-deployment packaging and test routing'
} finally {
    $env:LONGREACH_MODE_TEST_LOG=$previousLog
    if (Test-Path -LiteralPath $fixture) {
        $resolved=(Resolve-Path -LiteralPath $fixture).Path
        if ([IO.Path]::GetDirectoryName($resolved) -ne $temporaryRoot -or [IO.Path]::GetFileName($resolved) -notlike 'longreach-qt5-modes-*') { throw 'Unexpected fixture cleanup path' }
        for ($attempt=0; $attempt -lt 3; $attempt++) {
            try { Remove-Item -LiteralPath $resolved -Recurse -Force; break }
            catch { if ($attempt -eq 2) { throw }; Start-Sleep -Milliseconds 100 }
        }
    }
    Remove-Variable Qt5ModeAbi,Qt5ModeMissing,Qt5ModeId -Scope Global -ErrorAction SilentlyContinue
}
