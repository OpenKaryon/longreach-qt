# SPDX-License-Identifier: GPL-3.0-or-later
<# Routing regression checks only: Docker, downloads, APK tools and the emulator
   are replaced with recording stubs in a disposable fixture repository. #>
param([string]$RepoRoot = (Resolve-Path "$PSScriptRoot/../../..").Path)
$ErrorActionPreference = 'Stop'
$temporaryRoot = [IO.Path]::GetTempPath().TrimEnd('\','/')
$fixture = Join-Path $temporaryRoot ('longreach-qt6-modes-' + [guid]::NewGuid())
$global:Qt6ModeTestAbi = 'armeabi-v7a'
$global:Qt6ModeTestMissingImage = $false
$global:Qt6ModeTestWrongImage = $false
$global:Qt6ModeTestImageId = 'sha256:' + ('a' * 64)
$previousLog = $env:LONGREACH_MODE_TEST_LOG
function Assert-Mode([bool]$Condition, [string]$Message) {
    if (!$Condition) { throw $Message }
}
function Reset-ModeCalls { [IO.File]::WriteAllText($env:LONGREACH_MODE_TEST_LOG, '') ; $global:Qt6PackagingPhases.Clear() ; $global:Qt6ModeJobSecrets.Clear() }
function Get-ModeCalls { @(Get-Content -LiteralPath $env:LONGREACH_MODE_TEST_LOG) }
$global:Qt6ModeJobSecrets=[Collections.Generic.List[object]]::new()
function docker {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    if ($Arguments[0] -eq 'build') {
        $index=[Array]::IndexOf($Arguments,'--secret')
        if ($index -lt 0 -or $index+1 -ge $Arguments.Count) { throw 'SDK build omitted its jobs secret' }
        $secret=[regex]::Match($Arguments[$index+1],'^id=longreach-jobs,src=(.+)$')
        if (!$secret.Success) { throw 'SDK build changed its jobs secret binding' }
        $path=$secret.Groups[1].Value
        $global:Qt6ModeJobSecrets.Add(@{Path=$path;Value=[IO.File]::ReadAllText($path)})
    }
    Add-Content -LiteralPath $env:LONGREACH_MODE_TEST_LOG -Value ('docker|' + ($Arguments -join '|'))
    $global:LASTEXITCODE = 0
    if ($Arguments[0] -eq 'image' -and $Arguments[1] -eq 'inspect') {
        if ($Arguments[-1] -eq 'missing-host-fixture') { $global:LASTEXITCODE=1; return }
        if ($global:Qt6ModeTestMissingImage) { $global:LASTEXITCODE = 1; return }
        if ($Arguments -contains '{{json .}}') {
            $platform = if ($global:Qt6ModeTestWrongImage) { 'linux-amd64' } else { "android-lollipop-$global:Qt6ModeTestAbi" }
            return (@{Id=$global:Qt6ModeTestImageId; Os='linux'; Architecture='amd64'; Config=@{Labels=@{
                'org.openkaryon.longreach-qt.platform'=$platform
                'org.openkaryon.longreach-qt.android-api'='21'
                'org.openkaryon.longreach-qt.version'='6.8.5'
                'org.openkaryon.longreach-qt.compiler'='LLVM 21.1.8'
            }}} | ConvertTo-Json -Depth 5 -Compress)
        }
        return $global:Qt6ModeTestImageId
    }
}
$global:Qt6PackagingPhases=[Collections.Generic.List[string]]::new()
function Invoke-ModeKeytool {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    $global:Qt6PackagingPhases.Add('keytool')
    $key=$Arguments[[Array]::IndexOf($Arguments,'-keystore')+1]
    [IO.File]::WriteAllText($key,'synthetic initial signing key')
    $global:LASTEXITCODE=0
}
function python {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    # File-integrity behavior is exercised by test_android_artifacts.py.
    if ($Arguments[0] -like '*host-tools.py') {
        if (!(Test-Path -LiteralPath $Arguments[0] -PathType Leaf)) { throw 'Shared Java helper path was not resolved from its defining script' }
        $global:Qt6PackagingPhases.Add('java-home')
        $global:LASTEXITCODE=0
        return '{"launcher":"recording-jdk/bin/javac.exe","home":"recording-jdk","javac":"recording-jdk/bin/javac.exe","keytool":"Invoke-ModeKeytool"}'
    }
    if ($Arguments[0] -like '*artifact-manifest.py') {
        $global:Qt6PackagingPhases.Add($Arguments[1])
        if ($Arguments[1] -eq 'begin-apks') {
            $root=$Arguments[[Array]::IndexOf($Arguments,'--root')+1]
            foreach ($relative in @('apk/local-examples.jks')) {
                if (!(Test-Path -LiteralPath "$root/$relative" -PathType Leaf)) { throw 'begin-apks ran before all initial keys existed' }
            }
        }
        $global:LASTEXITCODE=0
        return
    }
    Add-Content -LiteralPath $env:LONGREACH_MODE_TEST_LOG -Value ('python|' + ($Arguments -join '|'))
    $global:LASTEXITCODE = 0
}
$global:Qt6ModeBusyProcess=''
function Get-Process {
    param($Name,$ErrorAction)
    if ($global:Qt6ModeBusyProcess -and @($Name | Where-Object { $global:Qt6ModeBusyProcess -like $_ }).Count) {
        return [pscustomobject]@{Name=$global:Qt6ModeBusyProcess}
    }
    return $null
}
function Invoke-WebRequest { throw 'Unexpected download in an offline routing test.' }
function Invoke-Mode([hashtable]$Parameters) {
    & "$fixture/scripts/build/qt6-android.ps1" @Parameters | Out-Null
}
function Expect-ModeFailure([hashtable]$Parameters, [string]$Pattern) {
    try { Invoke-Mode $Parameters } catch {
        Assert-Mode ($_.Exception.Message -match $Pattern) "Wrong failure: $($_.Exception.Message)"
        return
    }
    throw 'Expected a mode error'
}
try {
    New-Item -ItemType Directory -Path $fixture | Out-Null
    $env:LONGREACH_MODE_TEST_LOG = Join-Path $fixture 'calls.log'
    foreach ($relative in @('scripts/run/android/android-adb-endpoint.ps1','scripts/run/android/android-emulator-state.ps1','scripts/build/android-api21/build-options.ps1','scripts/build/android-api21/artifact-lock.ps1','scripts/build/android-api21/host-tools.py','scripts/build/android-api21/sdk-reports.py','scripts/build/android-api21/sdk-reports.ps1','scripts/build/android-api21/packaging-host.ps1','scripts/build/qt6-android.ps1','scripts/build/qt6-android/package-suite.ps1',
            'scripts/fetch/qt6-android.ps1','tests/expected-apps.txt')) {
        $destination = Join-Path $fixture $relative
        New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $RepoRoot $relative) -Destination $destination
    }
    New-Item -ItemType Directory -Path "$fixture/scripts/run", "$fixture/scripts/fetch/locks",
        "$fixture/android-sdk", "$fixture/downloads/android-lollipop" -Force | Out-Null
    @'
param($AndroidSdk,$OutputDirectory,$RunName,$Gpu,$CaseNames,$QtQuickBackend,$Abi,[switch]$DebugQtPlugins)
Add-Content -LiteralPath $env:LONGREACH_MODE_TEST_LOG -Value "test|$RunName|$Gpu|$($CaseNames -join ',')|$QtQuickBackend|$Abi"
if ($DebugQtPlugins) { Add-Content -LiteralPath $env:LONGREACH_MODE_TEST_LOG -Value "debug-qt-plugins" }
'@ | Set-Content "$fixture/scripts/run/qt6-android-suite.ps1"
    @'
param($QtSdk,$NativeLibrary,$RuntimeLibrary,$OutputDirectory,$AndroidSdk,$Package,$DeploymentDirectory,$Abi,$JavaTools)
$app = ([IO.Path]::GetFileName($NativeLibrary) -replace '^lib','' -replace ('_' + [regex]::Escape($Abi) + '\.so$'),'')
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $OutputDirectory "$app.apk"), $app)
Add-Content -LiteralPath $env:LONGREACH_MODE_TEST_LOG -Value "package|$app"
if (!$JavaTools -or $JavaTools.javac -cne 'recording-jdk/bin/javac.exe') { throw 'Suite did not freeze actual compiler selection' }
$global:Qt6PackagingPhases.Add('package')
'@ | Set-Content "$fixture/scripts/build/qt6-android/package.ps1"
    $output = Join-Path $fixture 'output with spaces'
    $entry = @{OutputDirectory=$output; AndroidSdk=''}

    # No Android SDK or source fetch should be needed for the default mode.
    Reset-ModeCalls
    Invoke-Mode $entry
    $calls = @(Get-ModeCalls)
    Assert-Mode ($calls.Count -eq 2 -and $calls[0] -like 'docker|image|inspect|*' -and
        $calls[1] -like "docker|run|*$global:Qt6ModeTestImageId|bash|*/build-examples.sh") 'Default mode did more than inspect/run examples'
    Assert-Mode ((Get-Content "$output/examples-sdk-image-id.txt") -eq $global:Qt6ModeTestImageId) 'Wrong SDK identity recorded'

    Reset-ModeCalls
    $global:Qt6ModeTestMissingImage = $true
    Expect-ModeFailure $entry 'Build it explicitly with -Mode sdk'
    Assert-Mode ((Get-ModeCalls).Count -eq 1) 'Missing image caused an automatic build'
    $global:Qt6ModeTestMissingImage = $false
    $global:Qt6ModeTestWrongImage = $true
    Reset-ModeCalls
    Expect-ModeFailure $entry 'not the Qt6'
    Assert-Mode ((Get-ModeCalls).Count -eq 1) 'Wrong image started work'
    $global:Qt6ModeTestWrongImage = $false

    Reset-ModeCalls
    Expect-ModeFailure @{Mode='sdk';OutputDirectory=$output;HostImage='missing-host-fixture'} 'docker exited with code'
    Assert-Mode ((Get-ModeCalls).Count -eq 1) 'Missing host SDK started downloads or compiler provisioning'
    Reset-ModeCalls
    Invoke-Mode @{Mode='examples';OutputDirectory=$output;SdkImage=$global:Qt6ModeTestImageId}
    Assert-Mode (@(Get-ModeCalls)[0] -like "*image|inspect|*|$global:Qt6ModeTestImageId") 'Immutable SDK image selection was dropped'

    # Real fetcher with tiny cached fixtures: sdk must ignore missing VM media.
    $sdkInputs = @('android-35.jar','build-tools_r36_linux.zip','android-ndk-r27-linux.zip')
    $testInputs = @('armeabi-v7a-21_r04.zip','tools_r24.4.1-windows.zip')
    $otherTestInputs = @('arm64-v8a-21_r04.zip','tools_r25.2.5-windows.zip','x86_64-21_r05.zip','emulator-windows_x64-9536276.zip')
    $sources = foreach ($name in ($sdkInputs + $testInputs + $otherTestInputs)) {
        $file = "$fixture/downloads/android-lollipop/$name"
        [IO.File]::WriteAllText($file, $name)
        $sha = (Get-FileHash $file).Hash.ToLowerInvariant()
        if ($name -in ($testInputs + $otherTestInputs)) { Remove-Item -LiteralPath $file }
        @{file=$name;sha256=$sha;encoding='binary';url='https://example.invalid/not-requested'}
    }
    @{sources=@($sources);shared_sources=@(@{file='llvm-fixture.tar.xz';url='https://example.invalid/not-requested';sha256='fixture'})} |
        ConvertTo-Json -Depth 5 | Set-Content "$fixture/scripts/fetch/locks/qt6-android-api21-inputs.json"
    Reset-ModeCalls
    Invoke-Mode @{Mode='sdk';OutputDirectory=$output;AndroidSdk='';ParallelJobs=3;NoCache=$true;DockerBuildFlagsJson='["--pull"]'}
    $calls = @(Get-ModeCalls)
    Assert-Mode (@($calls | Where-Object { $_ -like 'docker|build|*' }).Count -eq 2) 'SDK mode must refresh tools and build its SDK'
    foreach ($call in @($calls | Where-Object { $_ -like 'docker|build|*' })) {
        Assert-Mode ($call -like '*|--no-cache|*' -and $call -like '*|--pull|*' -and $call -like '*|--secret|id=longreach-jobs,src=*|*' -and $call -notlike '*PARALLEL_JOBS=*') 'SDK build controls were lost'
        Assert-Mode ($global:Qt6ModeJobSecrets.Count -gt 0 -and @($global:Qt6ModeJobSecrets | Where-Object { $_.Value -cne '3' -or (Test-Path -LiteralPath $_.Path) }).Count -eq 0) 'SDK jobs secret payload or cleanup changed'
    }
    Assert-Mode (@($calls | Where-Object { $_ -like 'docker|run|*' -or $_ -like 'package|*' -or $_ -like 'test|*' }).Count -eq 0) 'SDK mode entered another phase'
    Assert-Mode (@($calls | Where-Object { $_ -like 'python|*llvm-fixture*' }).Count -eq 1) 'SDK source fetch was omitted'
    Reset-ModeCalls
    Invoke-Mode @{Mode='sdk';Abi='x86_64';OutputDirectory=$output;AndroidSdk=''}
    Assert-Mode (@((Get-ModeCalls) | Where-Object { $_ -like 'docker|build|*' }).Count -eq 2) 'x86_64 SDK mode must refresh tools and SDK without VM media'
    Reset-ModeCalls
    Invoke-Mode @{SdkOnly=$true;OutputDirectory=$output;AndroidSdk=''}
    Assert-Mode (@((Get-ModeCalls) | Where-Object { $_ -like 'docker|build|*' }).Count -eq 2) 'Legacy SdkOnly alias stopped working'
    Reset-ModeCalls
    Expect-ModeFailure @{Mode='package';SdkOnly=$true;OutputDirectory=$output} 'cannot be combined'
    Assert-Mode ((Get-ModeCalls).Count -eq 0) 'Conflicting modes started work'

    # Tests must not fetch/hash SDK archives or installed Java compile inputs.
    foreach ($name in $sdkInputs) { Remove-Item -LiteralPath "$fixture/downloads/android-lollipop/$name" }
    foreach ($name in $testInputs) { [IO.File]::WriteAllText("$fixture/downloads/android-lollipop/$name", $name) }
    Reset-ModeCalls
    & "$fixture/scripts/fetch/qt6-android.ps1" -Scope test | Out-Null
    Assert-Mode ((Get-ModeCalls).Count -eq 0) 'Test-only fetch entered shared SDK sources'
    # x86_64 must select its r05 image and the independently pinned Emulator32,
    # while SDK files and every other ABI's media are absent.
    foreach ($name in $testInputs) { Remove-Item -LiteralPath "$fixture/downloads/android-lollipop/$name" }
    foreach ($name in @('x86_64-21_r05.zip','emulator-windows_x64-9536276.zip')) {
        [IO.File]::WriteAllText("$fixture/downloads/android-lollipop/$name", $name)
    }
    Reset-ModeCalls
    & "$fixture/scripts/fetch/qt6-android.ps1" -Scope test -Abi x86_64 | Out-Null
    Assert-Mode ((Get-ModeCalls).Count -eq 0) 'x86_64 test fetch entered SDK sources or another ABI'

    # Packaging uses saved deployments without inspecting or launching Docker.
    $apps = @(Get-Content "$fixture/tests/expected-apps.txt" | Where-Object { $_ -match '^[a-z]' -and $_ -ne 'smoke-runner' })
    foreach ($relative in @('sdk-packaging/jar','sdk-packaging/src/android/java/src','sdk-packaging/src/android/java/res')) {
        New-Item -ItemType Directory -Path "$output/$relative" -Force | Out-Null
    }
    [IO.File]::WriteAllText("$output/libc++_shared.so", 'fixture')
    [IO.File]::WriteAllText("$output/sdk-packaging/jar/Qt6Android.jar", 'fixture')
    foreach ($app in $apps) {
        New-Item -ItemType Directory -Path "$output/deployment/$app/libs/armeabi-v7a", "$output/deployment/$app/res/values" -Force | Out-Null
        [IO.File]::WriteAllText("$output/deployment/$app/libs/armeabi-v7a/lib${app}_armeabi-v7a.so", 'fixture')
        [IO.File]::WriteAllText("$output/deployment/$app/res/values/libs.xml", '<resources/>')
    }
    Reset-ModeCalls
    Invoke-Mode @{Mode='package';OutputDirectory=$output;AndroidSdk="$fixture/android-sdk"}
    $calls = @(Get-ModeCalls)
    Assert-Mode ($calls.Count -eq 8 -and @($calls | Where-Object { $_ -notlike 'package|*' }).Count -eq 0) 'Packaging entered another phase'
    Assert-Mode (@(Get-Content "$output/apk/packages.json" -Raw | ConvertFrom-Json).Count -eq 8) 'Incomplete APK manifest'
        Assert-Mode (@($global:Qt6PackagingPhases | Where-Object { $_ -eq 'keytool' }).Count -eq 1) 'Qt6 initial development key was not created exactly once'
        $phases=@($global:Qt6PackagingPhases | Where-Object { $_ -notin @('keytool','java-home') })
        $expected=@('check-examples','begin-apks')+@((1..8) | ForEach-Object { 'package' })+@('record-apks')
        Assert-Mode (($phases -join ',') -ceq ($expected -join ',')) ('Missing or reordered packaging manifest boundary: '+($phases -join ','))

    Remove-Item -LiteralPath "$output/deployment/network-gui/libs/armeabi-v7a/libnetwork-gui_armeabi-v7a.so"
    Reset-ModeCalls
    Expect-ModeFailure @{Mode='package';OutputDirectory=$output;AndroidSdk="$fixture/android-sdk"} 'Missing deployment'
    Assert-Mode ((Get-ModeCalls).Count -eq 0) 'Packaging started before checking all eight inputs'

    Reset-ModeCalls
    Invoke-Mode @{Mode='test';OutputDirectory=$output;AndroidSdk="$fixture/android-sdk";RunName='routing-check';Gpu='mesa';CaseNames=@('strict-cxx23');QtQuickBackend='software'}
    $calls = @(Get-ModeCalls)
    Assert-Mode ($calls.Count -eq 1 -and $calls[0] -eq 'test|routing-check|mesa|strict-cxx23|software|armeabi-v7a') 'Test mode entered another phase or dropped runner arguments'
    Reset-ModeCalls
    Invoke-Mode @{Mode='test';OutputDirectory=$output;AndroidSdk="$fixture/android-sdk";RunName='plugin-debug';CaseNames=@('quick-qml-gallery');DebugQtPlugins=$true}
    Assert-Mode (@(Get-ModeCalls).Count -eq 2 -and @(Get-ModeCalls)[1] -eq 'debug-qt-plugins') 'Plugin diagnostics were not forwarded to the test runner'
    # ABI isolation: an ARM64 client cannot silently consume an ARMv7 SDK.
    Reset-ModeCalls
    Expect-ModeFailure @{Mode='examples';Abi='arm64-v8a';OutputDirectory=$output} 'not the Qt6'
    Assert-Mode ((Get-ModeCalls).Count -eq 1) 'Wrong ABI launched a compiler'
    $global:Qt6ModeTestAbi = 'arm64-v8a'
    Reset-ModeCalls
    Invoke-Mode @{Mode='examples';Abi='arm64-v8a';OutputDirectory=$output}
    Assert-Mode (@(Get-ModeCalls)[0] -like '*longreach-qt6-android-lollipop-arm64-v8a:llvm21') 'ARM64 default selected the ARMv7 tag'
    Reset-ModeCalls
    Invoke-Mode @{Mode='test';Abi='arm64-v8a';OutputDirectory=$output;AndroidSdk="$fixture/android-sdk";RunName='arm64-check'}
    Assert-Mode (@(Get-ModeCalls)[0] -like 'test|arm64-check|*|arm64-v8a') 'Test mode dropped the selected ABI'
    # ARM64 packaging must select its own deployments and pass ABI to every APK.
    Reset-ModeCalls
    Expect-ModeFailure @{Mode='package';Abi='arm64-v8a';OutputDirectory=$output;AndroidSdk="$fixture/android-sdk"} 'Missing deployment'
    Assert-Mode ((Get-ModeCalls).Count -eq 0) 'ARM64 packaging consumed ARMv7 libraries'
    foreach ($app in $apps) {
        New-Item -ItemType Directory -Path "$output/deployment/$app/libs/arm64-v8a" -Force | Out-Null
        [IO.File]::WriteAllText("$output/deployment/$app/libs/arm64-v8a/lib${app}_arm64-v8a.so", 'arm64-fixture')
    }
    Reset-ModeCalls
    Invoke-Mode @{Mode='package';Abi='arm64-v8a';OutputDirectory=$output;AndroidSdk="$fixture/android-sdk"}
    Assert-Mode (@(Get-ModeCalls).Count -eq 8) 'ARM64 did not package eight applications'
    Assert-Mode (@(Get-Content "$output/apk/packages.json" -Raw | ConvertFrom-Json).Count -eq 8) 'Incomplete ARM64 package manifest'
    Reset-ModeCalls
    Expect-ModeFailure @{Mode='examples';Abi='x86_64';OutputDirectory=$output} 'not the Qt6'
    Assert-Mode ((Get-ModeCalls).Count -eq 1) 'x86_64 consumed an ARM64 SDK'
    $global:Qt6ModeTestAbi = 'x86_64'
    Reset-ModeCalls
    Invoke-Mode @{Mode='examples';Abi='x86_64';OutputDirectory=$output}
    Assert-Mode (@(Get-ModeCalls)[0] -like '*longreach-qt6-android-lollipop-x86_64:llvm21') 'Wrong x86_64 SDK tag'
    Reset-ModeCalls
    Expect-ModeFailure @{Mode='package';Abi='x86_64';OutputDirectory=$output;AndroidSdk="$fixture/android-sdk"} 'Missing deployment'
    Assert-Mode ((Get-ModeCalls).Count -eq 0) 'x86_64 packaging consumed ARM libraries'
    foreach ($app in $apps) {
        New-Item -ItemType Directory -Path "$output/deployment/$app/libs/x86_64" -Force | Out-Null
        [IO.File]::WriteAllText("$output/deployment/$app/libs/x86_64/lib${app}_x86_64.so", 'x86_64-fixture')
    }
    Reset-ModeCalls
    Invoke-Mode @{Mode='package';Abi='x86_64';OutputDirectory=$output;AndroidSdk="$fixture/android-sdk"}
    Assert-Mode (@(Get-ModeCalls).Count -eq 8) 'x86_64 did not package eight applications'
    Reset-ModeCalls
    Invoke-Mode @{Mode='test';Abi='x86_64';OutputDirectory=$output;AndroidSdk="$fixture/android-sdk";RunName='x86-64-check'}
    Assert-Mode (@(Get-ModeCalls)[0] -like 'test|x86-64-check|*|x86_64') 'Test mode dropped x86_64 ABI'
    Reset-ModeCalls
    Expect-ModeFailure @{Mode='examples';Abi='x86';OutputDirectory=$output} 'not the Qt6'
    Assert-Mode ((Get-ModeCalls).Count -eq 1) '32-bit x86 consumed an x86_64 SDK'
    $global:Qt6ModeTestAbi = 'x86'
    Reset-ModeCalls
    Invoke-Mode @{Mode='examples';Abi='x86';OutputDirectory=$output}
    Assert-Mode (@(Get-ModeCalls)[0] -like '*longreach-qt6-android-lollipop-x86:llvm21') 'Wrong 32-bit x86 SDK tag'
    Reset-ModeCalls
    Expect-ModeFailure @{Mode='package';Abi='x86';OutputDirectory=$output;AndroidSdk="$fixture/android-sdk"} 'Missing deployment'
    Assert-Mode ((Get-ModeCalls).Count -eq 0) '32-bit x86 packaging consumed 64-bit libraries'
    foreach ($app in $apps) {
        New-Item -ItemType Directory -Path "$output/deployment/$app/libs/x86" -Force | Out-Null
        [IO.File]::WriteAllText("$output/deployment/$app/libs/x86/lib${app}_x86.so", 'x86-fixture')
    }
    Reset-ModeCalls
    Invoke-Mode @{Mode='package';Abi='x86';OutputDirectory=$output;AndroidSdk="$fixture/android-sdk"}
    Assert-Mode (@(Get-ModeCalls).Count -eq 8) '32-bit x86 did not package eight applications'
    Reset-ModeCalls
    Invoke-Mode @{Mode='test';Abi='x86';OutputDirectory=$output;AndroidSdk="$fixture/android-sdk";RunName='x86-check'}
    Assert-Mode (@(Get-ModeCalls)[0] -like 'test|x86-check|*|x86') 'Test mode dropped 32-bit x86 ABI'
    foreach ($busyName in @('qemu-system-armel-headless','qemu-system-aarch64-headless','qemu-system-mips64el')) {
        $global:Qt6ModeBusyProcess=$busyName
        foreach ($busyAbi in @('armeabi-v7a','arm64-v8a','x86','x86_64')) {
            foreach ($busyMode in @('sdk','examples')) {
                Reset-ModeCalls
                $busyOptions=@{}+$entry
                $busyOptions.Abi=$busyAbi;$busyOptions.Mode=$busyMode
                Expect-ModeFailure $busyOptions 'Stop the Android emulator before compiling'
                Assert-Mode (@(Get-ModeCalls).Count -eq 0) "Busy $busyName entered a tool phase for $busyAbi/$busyMode"
            }
        }
    }
    $global:Qt6ModeBusyProcess=''
    Write-Output 'PASS: four independent modes, ready-image reuse, no implicit builds, legacy alias, fetch scopes and packaging preflight'
} finally {
    $env:LONGREACH_MODE_TEST_LOG = $previousLog
    if (Test-Path -LiteralPath $fixture) {
        $resolved = (Resolve-Path -LiteralPath $fixture).Path
        if ([IO.Path]::GetDirectoryName($resolved) -ne $temporaryRoot -or
                [IO.Path]::GetFileName($resolved) -notlike 'longreach-qt6-modes-*') {
            throw 'Unexpected fixture cleanup path'
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
    Remove-Variable Qt6ModeJobSecrets,Qt6ModeBusyProcess,Qt6PackagingPhases,Qt6ModeTestMissingImage,Qt6ModeTestWrongImage,Qt6ModeTestImageId,Qt6ModeTestAbi -Scope Global -ErrorAction SilentlyContinue
}
