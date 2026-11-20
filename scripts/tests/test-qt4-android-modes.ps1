# SPDX-License-Identifier: GPL-3.0-or-later
<# Phase routing and stale-artifact rejection without native builds or guests. #>
param([string]$RepoRoot=(Resolve-Path "$PSScriptRoot/../..").Path)
$ErrorActionPreference='Stop'
$parent=(New-Item -ItemType Directory -Force "$RepoRoot/build/fixtures").FullName
$fixture=Join-Path $parent ('qt4-android-modes-'+[guid]::NewGuid())
$previousLog=$env:LONGREACH_MODE_TEST_LOG
$global:Qt4ModeAbi='x86_64'
$global:Qt4ModeId='sha256:'+('a'*64)
$global:Qt4ModeMissing=$false
function Assert-Mode([bool]$Condition,[string]$Message) { if (!$Condition) { throw $Message } }
function Calls { @(Get-Content -LiteralPath $env:LONGREACH_MODE_TEST_LOG) }
function Reset-Calls { [IO.File]::WriteAllText($env:LONGREACH_MODE_TEST_LOG,'') }
function Get-Process { param($Name,$ErrorAction) return $null }
function docker {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    Add-Content $env:LONGREACH_MODE_TEST_LOG ('docker|'+($Arguments -join '|'))
    $global:LASTEXITCODE=0
    if ($Arguments[0] -eq 'image') {
        if ($global:Qt4ModeMissing) { $global:LASTEXITCODE=1; return }
        if ($Arguments -contains '{{json .}}') {
            return (@{Id=$global:Qt4ModeId;Os='linux';Architecture='amd64';Config=@{Labels=@{
                'org.openkaryon.longreach-qt.platform'="android-lollipop-$global:Qt4ModeAbi"
                'org.openkaryon.longreach-qt.android-api'='21'
                'org.openkaryon.longreach-qt.version'='4.8.7'
                'org.openkaryon.longreach-qt.compiler'='LLVM 21.1.8'
            }}} | ConvertTo-Json -Depth 5 -Compress)
        }
        return $global:Qt4ModeId
    }
    if ($Arguments[0] -eq 'create') { return ('b'*64) }
}
function Invoke-Mode([hashtable]$Options) { & "$fixture/scripts/build/qt4-android.ps1" @Options | Out-Null }
function Expect-Failure([hashtable]$Options,[string]$Message) {
    try { Invoke-Mode $Options } catch { Assert-Mode ($_.Exception.Message -match $Message) "Unexpected error: $_"; return }
    throw 'Expected mode failure'
}
try {
    New-Item -ItemType Directory -Path $fixture | Out-Null
    $env:LONGREACH_MODE_TEST_LOG="$fixture/calls.log"
    foreach ($relative in @('scripts/build/qt4-android.ps1','scripts/build/qt4-android/api21.ps1','scripts/build/qt4-android/host.ps1')) {
        $destination=Join-Path $fixture $relative
        New-Item -ItemType Directory -Force (Split-Path $destination) | Out-Null
        Copy-Item -LiteralPath (Join-Path $RepoRoot $relative) -Destination $destination
    }
    New-Item -ItemType Directory -Force "$fixture/scripts/fetch/locks","$fixture/scripts/run","$fixture/sdk/platforms/android-35" | Out-Null
    @'
param($Abi,$Scope,$AndroidSdk)
Add-Content $env:LONGREACH_MODE_TEST_LOG "fetch|$Abi|$Scope"
'@ | Set-Content "$fixture/scripts/fetch/qt4-android.ps1"
    @'
param($Abi,$RunName,$AndroidSdk,$OutputDirectory,$Profiles)
Add-Content $env:LONGREACH_MODE_TEST_LOG "test|$Abi|$RunName|$($Profiles -join ',')"
'@ | Set-Content "$fixture/scripts/run/qt4-android-api21-suite.ps1"
    @'
param($Abi,$Profile,$NativeDirectory,$OutputDirectory,$AndroidSdk,$AndroidJar)
[IO.File]::WriteAllText("$OutputDirectory/$Profile.apk",$Profile)
Add-Content $env:LONGREACH_MODE_TEST_LOG "package|$Abi|$Profile"
'@ | Set-Content "$fixture/scripts/build/qt4-android/package.ps1"
    [IO.File]::WriteAllText("$fixture/sdk/platforms/android-35/android.jar",'fixture jar')
    $jarHash=(Get-FileHash "$fixture/sdk/platforms/android-35/android.jar").Hash.ToLowerInvariant()
    @{sources=@(@{file='android-35.jar';sha256=$jarHash})} | ConvertTo-Json -Depth 4 | Set-Content "$fixture/scripts/fetch/locks/qt6-android-api21-inputs.json"
    $output="$fixture/output with spaces"
    $entry=@{Abi='x86_64';AndroidSdk="$fixture/sdk";OutputDirectory=$output}
    Reset-Calls
    Invoke-Mode $entry
    Assert-Mode (@((Calls) | Where-Object { $_ -like 'docker|run|*' }).Count -eq 1) 'Examples did not reuse one ready image'
    Assert-Mode (@((Calls) | Where-Object { $_ -like 'docker|build|*' -or $_ -like 'fetch|*' -or $_ -like 'package|*' }).Count -eq 0) 'Examples entered another phase'
    Assert-Mode ((Get-Content "$output/examples-sdk-image-id.txt") -eq $global:Qt4ModeId) 'Example SDK ID missing'
    $global:Qt4ModeMissing=$true
    Reset-Calls
    Expect-Failure $entry 'docker exited'
    Assert-Mode (@(Calls).Count -eq 1) 'Missing image triggered another phase'
    $global:Qt4ModeMissing=$false
    $global:Qt4ModeAbi='arm64-v8a'
    Reset-Calls
    Expect-Failure $entry 'not the Qt4'
    Assert-Mode (@(Calls).Count -eq 1) 'Wrong ABI entered another phase'
    $global:Qt4ModeAbi='x86_64'
    Reset-Calls
    Invoke-Mode ($entry+@{Mode='sdk'})
    Assert-Mode (@(Calls)[0] -eq 'fetch|x86_64|sdk') 'SDK fetch scope changed'
    Assert-Mode (@((Calls) | Where-Object { $_ -like 'docker|build|*|--target|sdk|*' }).Count -eq 1) 'SDK did not request its explicit stage'
    Reset-Calls
    Invoke-Mode ($entry+@{Mode='test';RunName='fixture-suite';Profiles=@('strict','quick')})
    Assert-Mode (@(Calls).Count -eq 1 -and @(Calls)[0] -eq 'test|x86_64|fixture-suite|strict,quick') 'Test mode compiled or lost its subset'
    $profiles=@('bootstrap','strict','core','selftest','widgets','graphics','painting','multimedia','gl','qml','network','quick')
    $built=foreach ($profile in $profiles) {
        [IO.File]::WriteAllText("$output/native/$profile.so",$profile)
        @{profile=$profile;native="$profile.so";sha256=(Get-FileHash "$output/native/$profile.so").Hash.ToLowerInvariant()}
    }
    $built | ConvertTo-Json | Set-Content "$output/native/examples-build.json"
    Reset-Calls
    Invoke-Mode ($entry+@{Mode='package'})
    Assert-Mode (@(Calls).Count -eq 12 -and @((Calls) | Where-Object { $_ -notlike 'package|x86_64|*' }).Count -eq 0) 'Package mode entered another phase'
    Assert-Mode (@(Get-Content "$output/apk-packages.json" -Raw | ConvertFrom-Json).Count -eq 12) 'Package manifest is incomplete'
    [IO.File]::WriteAllText("$output/native/gl.so",'changed')
    Reset-Calls
    Expect-Failure ($entry+@{Mode='package'}) 'Native artifact differs'
    Assert-Mode (@(Calls).Count -eq 0) 'Stale native package replaced an APK'
    ('sha256:'+('c'*64)) | Set-Content "$output/examples-sdk-image-id.txt"
    Expect-Failure ($entry+@{Mode='package'}) 'SDK/example identities differ'
    Reset-Calls
    Expect-Failure @{Mode='examples';AndroidSdk="$fixture/sdk"} 'API21 profiles only'
    Assert-Mode (@(Calls).Count -eq 0) 'Explicit API4 mode unexpectedly built an SDK'
    Write-Output 'PASS: explicit SDK build, ready-image clients, package/test isolation, stale SDK/native rejection, legacy default preserved'
} finally {
    $env:LONGREACH_MODE_TEST_LOG=$previousLog
    if (Test-Path -LiteralPath $fixture) {
        $resolved=(Resolve-Path -LiteralPath $fixture).Path
        if ([IO.Path]::GetDirectoryName($resolved) -ne $parent -or [IO.Path]::GetFileName($resolved) -notlike 'qt4-android-modes-*') { throw 'Unexpected fixture cleanup path' }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
    Remove-Variable Qt4ModeAbi,Qt4ModeId,Qt4ModeMissing -Scope Global -ErrorAction SilentlyContinue
}
