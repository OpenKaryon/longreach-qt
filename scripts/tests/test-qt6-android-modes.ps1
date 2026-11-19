# SPDX-License-Identifier: GPL-3.0-or-later
<# Routing regression checks only: Docker, downloads, APK tools and the emulator
   are replaced with recording stubs in a disposable fixture repository. #>
param([string]$RepoRoot = (Resolve-Path "$PSScriptRoot/../..").Path)
$ErrorActionPreference = 'Stop'
$temporaryRoot = [IO.Path]::GetTempPath().TrimEnd('\','/')
$fixture = Join-Path $temporaryRoot ('longreach-qt6-modes-' + [guid]::NewGuid())
$global:Qt6ModeTestMissingImage = $false
$global:Qt6ModeTestWrongImage = $false
$global:Qt6ModeTestImageId = 'sha256:' + ('a' * 64)
$previousLog = $env:LONGREACH_MODE_TEST_LOG
function Assert-Mode([bool]$Condition, [string]$Message) {
    if (!$Condition) { throw $Message }
}
function Reset-ModeCalls { [IO.File]::WriteAllText($env:LONGREACH_MODE_TEST_LOG, '') }
function Get-ModeCalls { @(Get-Content -LiteralPath $env:LONGREACH_MODE_TEST_LOG) }
function docker {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    Add-Content -LiteralPath $env:LONGREACH_MODE_TEST_LOG -Value ('docker|' + ($Arguments -join '|'))
    $global:LASTEXITCODE = 0
    if ($Arguments[0] -eq 'image' -and $Arguments[1] -eq 'inspect') {
        if ($Arguments[-1] -eq 'missing-host-fixture') { $global:LASTEXITCODE=1; return }
        if ($global:Qt6ModeTestMissingImage) { $global:LASTEXITCODE = 1; return }
        if ($Arguments -contains '{{json .}}') {
            $platform = if ($global:Qt6ModeTestWrongImage) { 'linux-amd64' } else { 'android-lollipop-armeabi-v7a' }
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
function python {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    # File-integrity behavior is exercised by test_android_artifacts.py.
    if ($Arguments[0] -like '*artifact-manifest.py') { $global:LASTEXITCODE=0; return }
    Add-Content -LiteralPath $env:LONGREACH_MODE_TEST_LOG -Value ('python|' + ($Arguments -join '|'))
    $global:LASTEXITCODE = 0
}
function Get-Process { param($Name,$ErrorAction) return $null }
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
    foreach ($relative in @('scripts/build/qt6-android.ps1','scripts/build/qt6-android/package-suite.ps1',
            'scripts/fetch/qt6-android.ps1','tests/expected-apps.txt')) {
        $destination = Join-Path $fixture $relative
        New-Item -ItemType Directory -Path (Split-Path $destination) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $RepoRoot $relative) -Destination $destination
    }
    New-Item -ItemType Directory -Path "$fixture/scripts/run", "$fixture/scripts/fetch/locks",
        "$fixture/android-sdk", "$fixture/downloads/android-lollipop" -Force | Out-Null
    @'
param($AndroidSdk,$OutputDirectory,$RunName,$Gpu,$CaseNames,$QtQuickBackend)
Add-Content -LiteralPath $env:LONGREACH_MODE_TEST_LOG -Value "test|$RunName|$Gpu|$($CaseNames -join ',')|$QtQuickBackend"
'@ | Set-Content "$fixture/scripts/run/qt6-android-suite.ps1"
    @'
param($QtSdk,$NativeLibrary,$RuntimeLibrary,$OutputDirectory,$AndroidSdk,$Package,$DeploymentDirectory)
$app = ([IO.Path]::GetFileName($NativeLibrary) -replace '^lib','' -replace '_armeabi-v7a\.so$','')
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $OutputDirectory "$app.apk"), $app)
Add-Content -LiteralPath $env:LONGREACH_MODE_TEST_LOG -Value "package|$app"
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
    $sources = foreach ($name in ($sdkInputs + $testInputs)) {
        $file = "$fixture/downloads/android-lollipop/$name"
        [IO.File]::WriteAllText($file, $name)
        $sha = (Get-FileHash $file).Hash.ToLowerInvariant()
        if ($name -in $testInputs) { Remove-Item -LiteralPath $file }
        @{file=$name;sha256=$sha;encoding='binary';url='https://example.invalid/not-requested'}
    }
    @{sources=@($sources);shared_sources=@(@{file='llvm-fixture.tar.xz';url='https://example.invalid/not-requested';sha256='fixture'})} |
        ConvertTo-Json -Depth 5 | Set-Content "$fixture/scripts/fetch/locks/qt6-android-api21-inputs.json"
    Reset-ModeCalls
    Invoke-Mode @{Mode='sdk';OutputDirectory=$output;AndroidSdk=''}
    $calls = @(Get-ModeCalls)
    Assert-Mode (@($calls | Where-Object { $_ -like 'docker|build|*' }).Count -eq 2) 'SDK mode must refresh tools and build its SDK'
    Assert-Mode (@($calls | Where-Object { $_ -like 'docker|run|*' -or $_ -like 'package|*' -or $_ -like 'test|*' }).Count -eq 0) 'SDK mode entered another phase'
    Assert-Mode (@($calls | Where-Object { $_ -like 'python|*llvm-fixture*' }).Count -eq 1) 'SDK source fetch was omitted'
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
    Remove-Item -LiteralPath "$output/deployment/network-gui/libs/armeabi-v7a/libnetwork-gui_armeabi-v7a.so"
    Reset-ModeCalls
    Expect-ModeFailure @{Mode='package';OutputDirectory=$output;AndroidSdk="$fixture/android-sdk"} 'Missing deployment'
    Assert-Mode ((Get-ModeCalls).Count -eq 0) 'Packaging started before checking all eight inputs'

    Reset-ModeCalls
    Invoke-Mode @{Mode='test';OutputDirectory=$output;AndroidSdk="$fixture/android-sdk";RunName='routing-check';Gpu='mesa';CaseNames=@('strict-cxx23');QtQuickBackend='software'}
    $calls = @(Get-ModeCalls)
    Assert-Mode ($calls.Count -eq 1 -and $calls[0] -eq 'test|routing-check|mesa|strict-cxx23|software') 'Test mode entered another phase or dropped runner arguments'
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
    Remove-Variable Qt6ModeTestMissingImage,Qt6ModeTestWrongImage,Qt6ModeTestImageId -Scope Global -ErrorAction SilentlyContinue
}
