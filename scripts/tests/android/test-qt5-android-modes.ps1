# SPDX-License-Identifier: GPL-3.0-or-later
<# Phase routing with recording tools; no native builds, downloads or guests. #>
param([string]$RepoRoot=(Resolve-Path "$PSScriptRoot/../../..").Path)
$ErrorActionPreference='Stop'
$temporaryRoot=[IO.Path]::GetTempPath().TrimEnd('\','/')
$fixture=Join-Path $temporaryRoot ('longreach-qt5-modes-'+[guid]::NewGuid())
$previousLog=$env:LONGREACH_MODE_TEST_LOG
$global:Qt5ModeAbi='armeabi-v7a'
$global:Qt5ModeMissing=$false
$global:Qt5ModeReportsMissing=$false
$global:Qt5ModeId='sha256:'+('a'*64)
$global:Qt5ReportPython=(@(Get-Command python -CommandType Application)[0]).Source
function Assert-Mode([bool]$Condition,[string]$Message) { if (!$Condition) { throw $Message } }
function Calls { @(Get-Content -LiteralPath $env:LONGREACH_MODE_TEST_LOG) }
# Check only the Qt5 SDK build; the Qt4 tools bootstrap has no target ABI.
function Assert-SdkAbi([string]$Abi,[string[]]$RecordedCalls=(Calls)) {
    $sdkCalls=@($RecordedCalls | Where-Object { $_ -like 'docker|build|*' -and $_ -like '*|--target|sdk|*' })
    Assert-Mode ($sdkCalls.Count -eq 1) "Expected exactly one Qt5 SDK build for $Abi"
    $arguments=$sdkCalls[0].Split('|')
    $abiArguments=@(for ($index=0; $index -lt $arguments.Count; $index++) {
        if ($arguments[$index] -like 'ANDROID_ABI=*') {
            Assert-Mode ($index -gt 0 -and $arguments[$index-1] -ceq '--build-arg') 'SDK ABI was not a build argument'
            $arguments[$index]
        }
    })
    Assert-Mode ($abiArguments.Count -eq 1 -and $abiArguments[0] -ceq "ANDROID_ABI=$Abi") "Missing, duplicate or wrong SDK ABI for $Abi"
}
function Reset-Calls { [IO.File]::WriteAllText($env:LONGREACH_MODE_TEST_LOG,'') ; $global:Qt5PackagingPhases.Clear() ; $global:Qt5ModeJobSecrets.Clear() }
$global:Qt5ModeBusyProcess=''
function Get-Process {
    param($Name,$ErrorAction)
    if ($global:Qt5ModeBusyProcess -and @($Name | Where-Object { $global:Qt5ModeBusyProcess -like $_ }).Count) {
        return [pscustomobject]@{Name=$global:Qt5ModeBusyProcess}
    }
    return $null
}
$global:Qt5ModeJobSecrets=[Collections.Generic.List[object]]::new()
function docker {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    if ($Arguments[0] -eq 'build') {
        $index=[Array]::IndexOf($Arguments,'--secret')
        if ($index -lt 0 -or $index+1 -ge $Arguments.Count) { throw 'SDK build omitted its jobs secret' }
        $secret=[regex]::Match($Arguments[$index+1],'^id=longreach-jobs,src=(.+)$')
        if (!$secret.Success) { throw 'SDK build changed its jobs secret binding' }
        $path=$secret.Groups[1].Value
        $global:Qt5ModeJobSecrets.Add(@{Path=$path;Value=[IO.File]::ReadAllText($path)})
    }
    Add-Content $env:LONGREACH_MODE_TEST_LOG ('docker|'+($Arguments -join '|'))
    $global:LASTEXITCODE=0
    if ($Arguments[0] -eq 'image' -and $Arguments[1] -eq 'inspect') {
        if ($global:Qt5ModeMissing) { $global:LASTEXITCODE=1; return }
        if ($Arguments -contains '{{json .}}') {
            $api=if ($global:Qt5ModeAbi -in @('armeabi-v7a','x86')) { '10' } else { '21' }
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
        if ($Arguments[1] -like '*:/opt/longreach-reports/*' -and $global:Qt5ModeReportsMissing) {
            $global:LASTEXITCODE=1
            return
        }
        if ($Arguments[1] -like '*:/opt/qt5-android-*') {
            foreach ($path in @('jar','src/android/java/src','src/android/java/res')) { New-Item -ItemType Directory -Force "$destination/$path" | Out-Null }
            [IO.File]::WriteAllText("$destination/jar/QtAndroid.jar",'fixture')
        } elseif ($Arguments[1] -like '*libc++_shared.so') {
            [IO.File]::WriteAllText($destination,'runtime')
        } elseif ($Arguments[1] -like '*:/opt/longreach-reports/*') {
            & $global:Qt5ReportPython "$fixture/report-fixture.py" $RepoRoot $destination $global:Qt5ModeAbi "$output/native/libc++_shared.so"
            if ($LASTEXITCODE) { throw 'Could not seed producer report directory' }
        }
    }
}
# File-integrity behavior is exercised by test_android_artifacts.py.
$global:Qt5PackagingPhases=[Collections.Generic.List[string]]::new()
function Invoke-ModeKeytool {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    $global:Qt5PackagingPhases.Add('keytool')
    $key=$Arguments[[Array]::IndexOf($Arguments,'-keystore')+1]
    [IO.File]::WriteAllText($key,'synthetic initial signing key')
    $global:LASTEXITCODE=0
}
function python {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    if ($Arguments[0] -like '*check-api10-api21-symbols.py') { $global:LASTEXITCODE=0; return }
    if ($Arguments[0] -like '*sdk-reports.py') {
        & $global:Qt5ReportPython @Arguments
        return
    }
    if ($Arguments[0] -like '*host-tools.py') {
        if (!(Test-Path -LiteralPath $Arguments[0] -PathType Leaf)) { throw 'Shared Java helper path was not resolved from its defining script' }
        $global:Qt5PackagingPhases.Add('java-home')
        $global:LASTEXITCODE=0
        return '{"launcher":"recording-jdk/bin/javac.exe","home":"recording-jdk","javac":"recording-jdk/bin/javac.exe","keytool":"Invoke-ModeKeytool"}'
    }
    if ($Arguments[0] -like '*artifact-manifest.py') {
        $global:Qt5PackagingPhases.Add($Arguments[1])
        if ($Arguments[1] -eq 'begin-apks') {
            $root=$Arguments[[Array]::IndexOf($Arguments,'--root')+1]
            foreach ($relative in @('apk/local-examples.jks','apk/extended/local-examples.jks')) {
                if (!(Test-Path -LiteralPath "$root/$relative" -PathType Leaf)) { throw 'begin-apks ran before all initial keys existed' }
            }
        }
        $global:LASTEXITCODE=0
        return
    }
}
function Invoke-Mode([hashtable]$Options) { & "$fixture/scripts/build/qt5-android.ps1" @Options | Out-Null }
function Expect-Failure([hashtable]$Options,[string]$Message) {
    try { Invoke-Mode $Options } catch { Assert-Mode ($_.Exception.Message -match $Message) "Unexpected error: $_"; return }
    throw 'Expected mode failure'
}
try {
    New-Item -ItemType Directory $fixture | Out-Null
    $env:LONGREACH_MODE_TEST_LOG="$fixture/calls.log"
    foreach ($relative in @('scripts/run/android/android-adb-endpoint.ps1','scripts/run/android/android-emulator-state.ps1','scripts/build/android-api21/build-options.ps1','scripts/build/android-api21/artifact-lock.ps1','scripts/build/android-api21/host-tools.py','scripts/build/android-api21/sdk-reports.py','scripts/build/android-api21/sdk-reports.ps1','scripts/build/android-api21/packaging-host.ps1','scripts/build/qt5-android.ps1','scripts/build/qt5-android/package-suite.ps1','tests/expected-apps.txt')) {
        $destination=Join-Path $fixture $relative
        New-Item -ItemType Directory -Force (Split-Path $destination) | Out-Null
        Copy-Item -LiteralPath (Join-Path $RepoRoot $relative) -Destination $destination
    }
    @'
import sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]) / 'scripts/tests/android'))
import android_sdk_report_fixtures as fixture
fixture.producer(Path(sys.argv[2]), 5, sys.argv[3], Path(sys.argv[4]).read_bytes())
'@ | Set-Content "$fixture/report-fixture.py"
    New-Item -ItemType Directory -Force "$fixture/scripts/run","$fixture/scripts/fetch","$fixture/android-sdk" | Out-Null
    @'
param($Abi,$Scope,$AndroidSdk)
Add-Content $env:LONGREACH_MODE_TEST_LOG "fetch|$Abi|$Scope"
'@ | Set-Content "$fixture/scripts/fetch/qt5-android.ps1"
    @'
param($Abi,$RunName,$AndroidSdk,$OutputDirectory,$Gpu,$CaseNames,[switch]$DebugQtPlugins,$QtQuickBackend,$Emulator)
if ($Emulator) { Add-Content $env:LONGREACH_MODE_TEST_LOG "emulator|$Emulator" }
Add-Content $env:LONGREACH_MODE_TEST_LOG "test|$Abi|$RunName|$($CaseNames -join ',')|$DebugQtPlugins"
'@ | Set-Content "$fixture/scripts/run/qt5-android-suite.ps1"
    @'
param($Abi,$QtSdk,$AndroidSdk,$NativeLibrary,$RuntimeLibrary,$DeploymentDirectory,$OutputDirectory,$Package,$JavaTools)
$app=([IO.Path]::GetFileName($NativeLibrary) -replace '^lib','' -replace ('_'+[regex]::Escape($Abi)+'\.so$'),'')
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
[IO.File]::WriteAllText("$OutputDirectory/$app.apk",$Package)
Add-Content $env:LONGREACH_MODE_TEST_LOG "package|$Abi|$app"
if (!$JavaTools -or $JavaTools.javac -cne 'recording-jdk/bin/javac.exe') { throw 'Suite did not freeze actual compiler selection' }
$global:Qt5PackagingPhases.Add('package')
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
    Invoke-Mode ($entry+@{Mode='sdk';Abi='x86_64';ParallelJobs=3;NoCache=$true;DockerBuildFlagsJson='["--pull"]'})
    Assert-Mode (@((Calls) | Where-Object { $_ -like 'docker|build|*' }).Count -eq 2) 'x86_64 SDK mode did not build once'
    Assert-SdkAbi 'x86_64'
    Assert-Mode (@((Calls) | Where-Object { $_ -eq 'fetch|x86_64|sdk' }).Count -eq 1) 'Wrong x86_64 SDK fetch scope'
    foreach ($call in @((Calls) | Where-Object { $_ -like 'docker|build|*' })) {
        Assert-Mode ($call -like '*|--no-cache|*' -and $call -like '*|--pull|*' -and $call -like '*|--secret|id=longreach-jobs,src=*|*' -and $call -notlike '*PARALLEL_JOBS=*') 'SDK build controls were lost'
        Assert-Mode ($global:Qt5ModeJobSecrets.Count -gt 0 -and @($global:Qt5ModeJobSecrets | Where-Object { $_.Value -cne '3' -or (Test-Path -LiteralPath $_.Path) }).Count -eq 0) 'SDK jobs secret payload or cleanup changed'
    }
    Reset-Calls
    Invoke-Mode ($entry+@{Mode='sdk';Abi='arm64-v8a'})
    Assert-Mode (@((Calls) | Where-Object { $_ -like 'docker|build|*' }).Count -eq 2) 'SDK mode did not build once'
    Assert-SdkAbi 'arm64-v8a'
    Assert-Mode (@((Calls) | Where-Object { $_ -like 'docker|run|*' -or $_ -like 'docker|create|*' -or $_ -like 'package|*' }).Count -eq 0) 'SDK mode entered examples'
    Assert-Mode (@((Calls) | Where-Object { $_ -eq 'fetch|arm64-v8a|sdk' }).Count -eq 1) 'Wrong SDK fetch scope'
    Reset-Calls
    Invoke-Mode ($entry+@{SdkOnly=$true;Abi='arm64-v8a'})
    Assert-Mode (@((Calls) | Where-Object { $_ -like 'docker|build|*' }).Count -eq 2) 'Legacy SdkOnly alias broke'
    Assert-SdkAbi 'arm64-v8a'
    Reset-Calls
    Expect-Failure ($entry+@{Mode='package';SdkOnly=$true}) 'cannot be combined'
    Assert-Mode (@(Calls).Count -eq 0) 'Conflicting modes started work'
    $apps=@(Get-Content "$fixture/tests/expected-apps.txt" | Where-Object { $_ -match '^[a-z]' -and $_ -ne 'smoke-runner' })
    foreach ($abi in @('armeabi-v7a','arm64-v8a','x86','x86_64')) {
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
        $expectedKeys=if ($abi -eq 'armeabi-v7a') { 2 } else { 0 }
        Assert-Mode (@($global:Qt5PackagingPhases | Where-Object { $_ -eq 'keytool' }).Count -eq $expectedKeys) 'Qt5 regenerated an existing development key or missed an initial key'
        $phases=@($global:Qt5PackagingPhases | Where-Object { $_ -notin @('keytool','java-home') })
        $expected=@('check-examples','begin-apks')+@((1..9) | ForEach-Object { 'package' })+@('record-apks')
        Assert-Mode (($phases -join ',') -ceq ($expected -join ',')) ('Missing or reordered packaging manifest boundary: '+($phases -join ','))

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
    Reset-Calls
    Invoke-Mode ($entry+@{Mode='test';Abi='x86';Emulator='already-built/emulator-x86.exe'})
    Assert-Mode (@(Calls).Count -eq 2 -and @(Calls)[0] -eq 'emulator|already-built/emulator-x86.exe') 'Test mode lost the explicit emulator'
    Reset-Calls
    Expect-Failure ($entry+@{Mode='examples';Abi='x86';Emulator='unused.exe'}) 'requires -Mode test -Abi x86'
    Assert-Mode (@(Calls).Count -eq 0) 'An invalid emulator override started work'
    Expect-Failure ($entry+@{Mode='examples';Abi='x86'}) 'not the Qt5'
    Assert-Mode (@(Calls).Count -eq 1) '32-bit x86 consumed a 64-bit SDK'
    $global:Qt5ModeAbi='x86'
    $global:Qt5ModeReportsMissing=$true
    Reset-Calls
    Expect-Failure ($entry+@{Mode='examples';Abi='x86'}) 'Missing API10 SDK producer reports'
    Assert-Mode (@((Calls) | Where-Object { $_ -like 'docker|run|*' }).Count -eq 0) 'Missing producer reports started a consumer build'
    Assert-Mode (@((Calls) | Where-Object { $_ -like 'docker|rm|*' }).Count -eq 1) 'Failed export leaked its temporary container'
    $global:Qt5ModeReportsMissing=$false
    Reset-Calls
    Invoke-Mode ($entry+@{Mode='examples';Abi='x86'})
    Assert-Mode (@(Calls)[0] -like '*longreach-qt5-android-gingerbread-x86:llvm21') 'Wrong x86 API10 default tag'
    Reset-Calls
    Invoke-Mode ($entry+@{Mode='sdk';Abi='x86'})
    Assert-Mode (@((Calls) | Where-Object { $_ -eq 'fetch|x86|sdk' }).Count -eq 1) 'Wrong x86 SDK fetch ABI'
    Reset-Calls
    Invoke-Mode ($entry+@{Mode='test';Abi='x86';RunName='x86-api10-routing'})
    Assert-Mode (@(Calls).Count -eq 1 -and @(Calls)[0] -eq 'test|x86|x86-api10-routing||False') 'x86 test mode lost API10 routing'
    foreach ($abi in @('armeabi-v7a','arm64-v8a','x86','x86_64')) {
        Reset-Calls
        Invoke-Mode ($entry+@{Mode='sdk';Abi=$abi})
        Assert-SdkAbi $abi
        Assert-Mode (@((Calls) | Where-Object { $_ -eq "fetch|$abi|sdk" }).Count -eq 1) 'SDK fetch ABI differed from build ABI'
    }
    # A missing/wrong/duplicate ABI must fail even though the build count stays two.
    foreach ($record in @('docker|build|--target|sdk|context',
            'docker|build|--build-arg|ANDROID_ABI=armeabi-v7a|--target|sdk|context',
            'docker|build|ANDROID_ABI=x86_64|--target|sdk|context',
            'docker|build|--build-arg|ANDROID_ABI=x86_64|--build-arg|ANDROID_ABI=x86_64|--target|sdk|context')) {
        $failed=$false
        try { Assert-SdkAbi 'x86_64' @('docker|build|--file|qt4-tools|context',$record) } catch { $failed=$true }
        Assert-Mode $failed 'SDK ABI check accepted an invalid two-build recording'
    }
    foreach ($busyName in @('qemu-system-armel-headless','qemu-system-aarch64-headless','qemu-system-mips64el')) {
        $global:Qt5ModeBusyProcess=$busyName
        foreach ($busyAbi in @('armeabi-v7a','arm64-v8a','x86','x86_64')) {
            foreach ($busyMode in @('sdk','examples')) {
                Reset-Calls
                $busyOptions=@{}+$entry
                $busyOptions.Abi=$busyAbi;$busyOptions.Mode=$busyMode
                Expect-Failure $busyOptions 'Stop the Android emulator before compiling'
                Assert-Mode (@(Calls).Count -eq 0) "Busy $busyName entered a tool phase for $busyAbi/$busyMode"
            }
        }
    }
    $global:Qt5ModeBusyProcess=''
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
    Remove-Variable Qt5ModeJobSecrets,Qt5ModeBusyProcess,Qt5ReportPython,Qt5PackagingPhases,Qt5ModeAbi,Qt5ModeMissing,Qt5ModeReportsMissing,Qt5ModeId -Scope Global -ErrorAction SilentlyContinue
}
