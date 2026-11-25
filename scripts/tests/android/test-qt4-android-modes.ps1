# SPDX-License-Identifier: GPL-3.0-or-later
<# Phase routing and stale-artifact rejection without native builds or guests. #>
param([string]$RepoRoot=(Resolve-Path "$PSScriptRoot/../../..").Path)
$ErrorActionPreference='Stop'
$parent=(New-Item -ItemType Directory -Force "$RepoRoot/build/fixtures").FullName
$fixture=Join-Path $parent ('qt4-android-modes-'+[guid]::NewGuid())
$previousLog=$env:LONGREACH_MODE_TEST_LOG
$global:Qt4ModeAbi='x86_64'
$global:Qt4ModeId='sha256:'+('a'*64)
$global:Qt4ModeMissing=$false
$global:Qt4ModeFailPackage=''
$global:Qt4ModeCacheBusy=$false
$global:Qt4ModePython=(Get-Command python).Source
function python {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    if ($Arguments[0] -like '*host-tools.py') {
        $global:LASTEXITCODE=0
        return '{"launcher":"recording-jdk/bin/javac.exe","home":"recording-jdk","javac":"recording-jdk/bin/javac.exe","keytool":"recording-jdk/bin/keytool.exe"}'
    }
    if ($Arguments[0] -match '[\\/]qt4-android[\\/]artifact-manifest\.py$') {
        & $global:Qt4ModePython "$fixture/tool-receipt-driver.py" @Arguments
    } else { & $global:Qt4ModePython @Arguments }
}
function Assert-Mode([bool]$Condition,[string]$Message) { if (!$Condition) { throw $Message } }
function Calls { @(Get-Content -LiteralPath $env:LONGREACH_MODE_TEST_LOG) }
function Reset-Calls { [IO.File]::WriteAllText($env:LONGREACH_MODE_TEST_LOG,'') ; $global:Qt4ModeJobSecrets.Clear() }
$global:Qt4ModeBusyProcess=''
function Get-Process {
    param($Name,$ErrorAction)
    if ($global:Qt4ModeBusyProcess -and @($Name | Where-Object { $global:Qt4ModeBusyProcess -like $_ }).Count) {
        return [pscustomobject]@{Name=$global:Qt4ModeBusyProcess}
    }
    return $null
}
$global:Qt4ModeJobSecrets=[Collections.Generic.List[object]]::new()
function docker {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    if ($Arguments[0] -eq 'build') {
        $index=[Array]::IndexOf($Arguments,'--secret')
        if ($index -lt 0 -or $index+1 -ge $Arguments.Count) { throw 'SDK build omitted its jobs secret' }
        $secret=[regex]::Match($Arguments[$index+1],'^id=longreach-jobs,src=(.+)$')
        if (!$secret.Success) { throw 'SDK build changed its jobs secret binding' }
        $path=$secret.Groups[1].Value
        $global:Qt4ModeJobSecrets.Add(@{Path=$path;Value=[IO.File]::ReadAllText($path)})
    }
    Add-Content $env:LONGREACH_MODE_TEST_LOG ('docker|'+($Arguments -join '|'))
    $global:LASTEXITCODE=0
    if ($Arguments[0] -eq 'image') {
        if ($global:Qt4ModeMissing) { $global:LASTEXITCODE=1; return }
        if ($Arguments -contains '{{json .}}') {
            return (@{Id=$global:Qt4ModeId;Os='linux';Architecture='amd64';Config=@{Labels=@{
                'org.openkaryon.longreach-qt.platform'="android-$(if ($global:Qt4ModeAbi -eq 'x86') { 'gingerbread' } else { 'lollipop' })-$global:Qt4ModeAbi"
                'org.openkaryon.longreach-qt.android-api'="$(if ($global:Qt4ModeAbi -eq 'x86') { '10' } else { '21' })"
                'org.openkaryon.longreach-qt.version'='4.8.7'
                'org.openkaryon.longreach-qt.compiler'='LLVM 21.1.8'
            }}} | ConvertTo-Json -Depth 5 -Compress)
        }
        return $global:Qt4ModeId
    }
    if ($Arguments[0] -eq 'ps' -and $global:Qt4ModeCacheBusy -and
            @($Arguments | Where-Object { $_ -like 'volume=*' }).Count) {
        return ('c'*64+' inherited-client')
    }
    if ($Arguments[0] -eq 'create') { return ('b'*64) }
    if ($Arguments[0] -eq 'cp' -and $Arguments[1] -like '*longreach-reports/*') {
        Write-ModeNative "$output/native/libc++_shared.so" 'runtime'
        & $global:Qt4ModePython "$fixture/report-fixture.py" $RepoRoot producer $Arguments[2] $global:Qt4ModeAbi "$output/native/libc++_shared.so" $global:Qt4ModeId
        if ($LASTEXITCODE) { throw 'Could not seed Qt4 SDK report producer' }
    }
    if ($Arguments[0] -eq 'run') {
        Assert-Mode ($Arguments -contains '--init') 'Client container lost its init process'
        $name=$Arguments[[Array]::IndexOf($Arguments,'--name')+1]
        Assert-Mode ($name -like "longreach-qt4-$global:Qt4ModeAbi-clients-*") 'Client container lost its stable name'
        Assert-Mode ($Arguments -contains "type=volume,source=$name,target=/work") 'Client container name differs from the retained cache'
        Assert-Mode ($Arguments -contains "LONGREACH_SDK_IMAGE_ID=$global:Qt4ModeId") 'Client container lost its SDK binding'
        $built=foreach ($profile in @('bootstrap','strict','core','selftest','widgets','graphics','painting','multimedia','gl','qml','network','quick')) {
            Write-ModeNative "$output/native/$profile.so" $profile
            @{profile=$profile;native="$profile.so";sha256=(Get-FileHash "$output/native/$profile.so").Hash.ToLowerInvariant()}
        }
        Write-ModeManifest $built
    }
}
function Write-ModeNative([string]$Path,[string]$Text) {
    $header=[byte[]]::new(64)
    $header[0]=127;$header[1]=69;$header[2]=76;$header[3]=70;$header[5]=1
    $header[4]=if($global:Qt4ModeAbi -eq 'x86'){1}else{2}
    $header[6]=1;$header[16]=3;$header[20]=1
    if($header[4] -eq 1){$header[40]=52}else{$header[52]=64}
    $header[18]=switch($global:Qt4ModeAbi){'x86'{3};'x86_64'{62};default{183}}
    [IO.File]::WriteAllBytes($Path,($header+[Text.Encoding]::UTF8.GetBytes($Text)))
}
function Write-ModeManifest($Built) {
    Write-ModeNative "$output/native/libc++_shared.so" 'runtime'
    @{schema_version=2;abi=$global:Qt4ModeAbi;api=$(if($global:Qt4ModeAbi -eq 'x86'){10}else{21});
      sdk_image_id=$global:Qt4ModeId;clients=@($Built);runtime_sha256=(Get-FileHash "$output/native/libc++_shared.so").Hash.ToLowerInvariant()} |
      ConvertTo-Json -Depth 6 | Set-Content "$output/native/examples-build.json"
}
function Complete-ModeGeneration {
    & $global:Qt4ModePython "$fixture/report-fixture.py" $RepoRoot export "$output/sdk-reports" $global:Qt4ModeAbi "$output/native/libc++_shared.so" $global:Qt4ModeId
    if ($LASTEXITCODE) { throw 'Could not bind current Qt4 report fixture' }
    foreach ($command in @('begin','finish')) {
        python "$fixture/scripts/build/qt4-android/artifact-manifest.py" $command --root $output --abi $global:Qt4ModeAbi --sdk-image-id $global:Qt4ModeId --artifact-lease-held | Out-Null
        if ($LASTEXITCODE) { throw 'Fixture native producer did not seal a generation' }
    }
}
function Invoke-Mode([hashtable]$Options) { & "$fixture/scripts/build/qt4-android.ps1" @Options | Out-Null }
function Expect-Failure([hashtable]$Options,[string]$Message) {
    try { Invoke-Mode $Options } catch { Assert-Mode ($_.Exception.Message -match $Message) "Unexpected error: $_"; return }
    throw 'Expected mode failure'
}
try {
    New-Item -ItemType Directory -Path $fixture | Out-Null
    $env:LONGREACH_MODE_TEST_LOG="$fixture/calls.log"
    foreach ($relative in @('scripts/run/android/android-adb-endpoint.ps1','scripts/run/android/android-emulator-state.ps1','scripts/build/android-api21/build-options.ps1','scripts/build/android-api21/artifact-lock.ps1','scripts/build/android-api21/host-tools.py','scripts/build/android-api21/sdk-reports.py','scripts/build/android-api21/sdk-reports.ps1','scripts/build/android-api21/packaging-host.ps1','scripts/build/android-api21/native-abi.py','scripts/build/android-api21/artifact-manifest.py','tests/expected-apps.txt','scripts/build/qt4-android/artifact-manifest.py','scripts/build/qt4-android.ps1','scripts/build/qt4-android/api21.ps1','scripts/build/qt4-android/host.ps1','scripts/build/qt4-android/client-cache.ps1')) {
        $destination=Join-Path $fixture $relative
        New-Item -ItemType Directory -Force (Split-Path $destination) | Out-Null
        Copy-Item -LiteralPath (Join-Path $RepoRoot $relative) -Destination $destination
    }
    @'
import importlib.util, sys
spec = importlib.util.spec_from_file_location('qt4_fixture_manifest', sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
# Keep real generation/ZIP/lease checks; replace the host-tool snapshot only.
module.common.packaging_inputs = lambda *args: {'fixture': 'recording host tools'}
try:
    module.main(sys.argv[2:])
except (OSError, ValueError, KeyError, RuntimeError) as error:
    sys.exit(f'Qt4 Android artifact validation failed: {error}')
'@ | Set-Content "$fixture/tool-receipt-driver.py"
    @'
import sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]) / 'scripts/tests/android'))
import android_sdk_report_fixtures as fixture
action, destination, abi, runtime, sdk = sys.argv[2:]
if action == 'producer':
    fixture.producer(Path(destination), 4, abi, Path(runtime).read_bytes())
else:
    source = fixture.producer(Path(destination) / ('.sdk-report-input-fixture-' + abi), 4, abi, Path(runtime).read_bytes())
    fixture.reports.export(source, Path(destination), 4, abi, sdk)
'@ | Set-Content "$fixture/report-fixture.py"
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
param($Abi,$Profile,$NativeDirectory,$OutputDirectory,$AndroidSdk,$AndroidJar,$JavaTools)
if ($global:Qt4ModeFailPackage -eq $Profile) { throw 'fixture partial packaging failure' }
$apk="$OutputDirectory/$Profile.apk"
[IO.File]::Delete($apk)
$archive=[IO.Compression.ZipFile]::Open($apk,[IO.Compression.ZipArchiveMode]::Create)
try {
    [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,"$NativeDirectory/$Profile.so","lib/$Abi/libdonut_probe.so") | Out-Null
    [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,"$NativeDirectory/libc++_shared.so","lib/$Abi/libc++_shared.so") | Out-Null
} finally { $archive.Dispose() }
Add-Content $env:LONGREACH_MODE_TEST_LOG "package|$Abi|$Profile"
'@ | Set-Content "$fixture/scripts/build/qt4-android/package.ps1"
    [IO.File]::WriteAllText("$fixture/sdk/platforms/android-35/android.jar",'fixture jar')
    $jarHash=(Get-FileHash "$fixture/sdk/platforms/android-35/android.jar").Hash.ToLowerInvariant()
    @{sources=@(@{file='android-35.jar';sha256=$jarHash})} | ConvertTo-Json -Depth 4 | Set-Content "$fixture/scripts/fetch/locks/qt6-android-api21-inputs.json"
    $output=(New-Item -ItemType Directory -Force "$fixture/output with spaces").FullName
    [IO.File]::WriteAllText("$output/local-probe.jks",'fixture signing input')
    $entry=@{Abi='x86_64';AndroidSdk="$fixture/sdk";OutputDirectory=$output}
    Reset-Calls
    Invoke-Mode $entry
    Assert-Mode (@((Calls) | Where-Object { $_ -like 'docker|run|*' }).Count -eq 1) 'Examples did not reuse one ready image'
    Assert-Mode (@((Calls) | Where-Object { $_ -like 'docker|build|*' -or $_ -like 'fetch|*' -or $_ -like 'package|*' }).Count -eq 0) 'Examples entered another phase'
    Assert-Mode ((Get-Content "$output/examples-sdk-image-id.txt") -eq $global:Qt4ModeId) 'Example SDK ID missing'
    $completedManifest=[IO.File]::ReadAllText("$output/examples-manifest.json")
    $global:Qt4ModeCacheBusy=$true
    Reset-Calls
    Expect-Failure $entry 'Qt4 client cache is busy'
    Assert-Mode (@((Calls) | Where-Object { $_ -like 'docker|create|*' -or $_ -like 'docker|run|*' }).Count -eq 0) 'Busy cache entered a producer'
    Assert-Mode ([IO.File]::ReadAllText("$output/examples-manifest.json") -eq $completedManifest -and
        !(Test-Path "$output/examples-in-progress.json")) 'Busy cache invalidated its prior native generation'
    $global:Qt4ModeCacheBusy=$false
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
    Invoke-Mode ($entry+@{Mode='sdk';ParallelJobs=3;NoCache=$true;DockerBuildFlagsJson='["--pull"]'})
    Assert-Mode (@(Calls)[0] -eq 'fetch|x86_64|sdk') 'SDK fetch scope changed'
    Assert-Mode (@((Calls) | Where-Object { $_ -like 'docker|build|*|--target|sdk|*' }).Count -eq 1) 'SDK did not request its explicit stage'
    foreach ($call in @((Calls) | Where-Object { $_ -like 'docker|build|*' })) {
        Assert-Mode ($call -like '*|--no-cache|*' -and $call -like '*|--pull|*' -and $call -like '*|--secret|id=longreach-jobs,src=*|*' -and $call -notlike '*PARALLEL_JOBS=*') 'SDK build controls were lost'
        Assert-Mode ($global:Qt4ModeJobSecrets.Count -gt 0 -and @($global:Qt4ModeJobSecrets | Where-Object { $_.Value -cne '3' -or (Test-Path -LiteralPath $_.Path) }).Count -eq 0) 'SDK jobs secret payload or cleanup changed'
    }
    $profiles=@('bootstrap','strict','core','selftest','widgets','graphics','painting','multimedia','gl','qml','network','quick')
    $built=foreach ($profile in $profiles) {
        Write-ModeNative "$output/native/$profile.so" $profile
        @{profile=$profile;native="$profile.so";sha256=(Get-FileHash "$output/native/$profile.so").Hash.ToLowerInvariant()}
    }
    Write-ModeManifest $built
    Complete-ModeGeneration
    Reset-Calls
    Invoke-Mode ($entry+@{Mode='package'})
    Assert-Mode (@(Calls).Count -eq 12 -and @((Calls) | Where-Object { $_ -notlike 'package|x86_64|*' }).Count -eq 0) 'Package mode entered another phase'
    Assert-Mode (@(Get-Content "$output/apk-packages.json" -Raw | ConvertFrom-Json).Count -eq 12) 'Package manifest is incomplete'
    Reset-Calls
    Invoke-Mode ($entry+@{Mode='test';RunName='fixture-suite';Profiles=@('strict','quick')})
    Assert-Mode (@(Calls).Count -eq 1 -and @(Calls)[0] -eq 'test|x86_64|fixture-suite|strict,quick') 'Test mode compiled or lost its subset'
    $nativeManifest=[IO.File]::ReadAllBytes("$output/native/examples-build.json")
    [IO.File]::AppendAllText("$output/native/examples-build.json","`n")
    Reset-Calls
    Expect-Failure ($entry+@{Mode='test'}) 'generation or producer reports changed'
    Assert-Mode (@(Calls).Count -eq 0) 'Changed same-SDK native manifest reached the runner'
    [IO.File]::WriteAllBytes("$output/native/examples-build.json",$nativeManifest)
    $global:Qt4ModeFailPackage='painting'
    Reset-Calls
    Expect-Failure ($entry+@{Mode='package'}) 'fixture partial packaging failure'
    Assert-Mode (!(Test-Path "$output/apk-manifest.json") -and (Test-Path "$output/apk-in-progress.json")) 'Partial packaging retained a completion receipt'
    Reset-Calls
    Expect-Failure ($entry+@{Mode='test'}) 'APK generation is incomplete'
    Assert-Mode (@(Calls).Count -eq 0) 'Partial APK generation reached the runner'
    # Model explicit recovery after the failed producer has stopped.
    $global:Qt4ModeFailPackage=''
    Remove-Item -LiteralPath "$output/apk-in-progress.json"
    Invoke-Mode ($entry+@{Mode='package'})
    [IO.File]::WriteAllText("$output/native/gl.so",'changed')
    Reset-Calls
    Expect-Failure ($entry+@{Mode='package'}) 'Native artifact differs'
    Assert-Mode (@(Calls).Count -eq 0) 'Stale native package replaced an APK'
    ('sha256:'+('c'*64)) | Set-Content "$output/examples-sdk-image-id.txt"
    Expect-Failure ($entry+@{Mode='package'}) 'SDK/example identities differ'
    Reset-Calls
    # API4's real four-phase contracts are exercised by test-qt4-api4-sdk.ps1.
    # This fixture observes only the public dispatch boundary.
    @'
param($Mode,$ParallelJobs,$NoCache,$DockerBuildFlagsJson,$SdkImage,$InputDirectory,$OutputDirectory,$AndroidSdk,$Profiles)
Add-Content $env:LONGREACH_MODE_TEST_LOG "api4|$Mode|$ParallelJobs"
'@ | Set-Content "$fixture/scripts/build/qt4-android/api4.ps1"
    Invoke-Mode @{Mode='examples';AndroidSdk="$fixture/sdk"}
    Assert-Mode (@(Calls).Count -eq 1 -and @(Calls)[0] -eq 'api4|examples|2') 'Explicit API4 mode missed its own dispatcher'
    $x86=@{} + $entry
    $x86.Abi='x86'
    Reset-Calls
    Expect-Failure $x86 'not the Qt4'
    Assert-Mode (@(Calls).Count -eq 1) 'x86 consumed an x86_64 SDK'
    $global:Qt4ModeAbi='x86'
    Reset-Calls
    Invoke-Mode $x86
    Assert-Mode (@(Calls)[0] -like '*longreach-qt4-android-gingerbread-x86:llvm21') 'Wrong x86 default SDK tag'
    Assert-Mode (@((Calls) | Where-Object { $_ -like 'docker|build|*' -or $_ -like 'fetch|*' }).Count -eq 0) 'x86 clients rebuilt the SDK'
    Reset-Calls
    Invoke-Mode ($x86+@{Mode='sdk'})
    Assert-Mode (@(Calls)[0] -eq 'fetch|x86|sdk') 'Wrong API10 x86 fetch routing'
    $built=foreach ($profile in $profiles) {
        Write-ModeNative "$output/native/$profile.so" $profile
        @{profile=$profile;native="$profile.so";sha256=(Get-FileHash "$output/native/$profile.so").Hash.ToLowerInvariant()}
    }
    Write-ModeManifest $built
    Complete-ModeGeneration
    Reset-Calls
    Invoke-Mode ($x86+@{Mode='package'})
    $x86Packages=@(Get-Content "$output/apk-packages.json" -Raw | ConvertFrom-Json)
    Assert-Mode (@(Calls).Count -eq 12 -and $x86Packages.Count -eq 12) 'x86 packaging lost a client'
    Assert-Mode (@($x86Packages | Where-Object { $_.abi -ne 'x86' -or $_.api -ne 10 }).Count -eq 0) 'x86 packaging selected API21 metadata'
    Reset-Calls
    Invoke-Mode ($x86+@{Mode='test';RunName='x86-routing';Profiles=@('strict','quick')})
    Assert-Mode (@(Calls).Count -eq 1 -and @(Calls)[0] -eq 'test|x86|x86-routing|strict,quick') 'x86 test routing lost profiles or compiled code'
    $arm=@{} + $entry
    $arm.Abi='arm64-v8a'
    Reset-Calls
    Expect-Failure $arm 'not the Qt4'
    Assert-Mode (@(Calls).Count -eq 1) 'ARM64 consumed an x86 SDK'
    $global:Qt4ModeAbi='arm64-v8a'
    Reset-Calls
    Invoke-Mode $arm
    Assert-Mode (@(Calls)[0] -like '*longreach-qt4-android-lollipop-arm64-v8a:llvm21') 'Wrong ARM64 default SDK tag'
    Assert-Mode (@((Calls) | Where-Object { $_ -like 'docker|build|*' -or $_ -like 'fetch|*' }).Count -eq 0) 'ARM64 clients rebuilt the SDK'
    Reset-Calls
    Invoke-Mode ($arm+@{Mode='sdk'})
    Assert-Mode (@(Calls)[0] -eq 'fetch|arm64-v8a|sdk') 'Wrong ARM64 fetch routing'
    Reset-Calls
    $wrong=Get-Content "$output/native/examples-build.json" -Raw | ConvertFrom-Json
    $wrong.abi='x86'
    $wrong | ConvertTo-Json -Depth 6 | Set-Content "$output/native/examples-build.json"
    Expect-Failure ($arm+@{Mode='package'}) 'Native generation ABI'
    # Model matching producer hashes around the wrong ELF ABI.
    $global:Qt4ModeAbi='x86'
    $built=foreach ($profile in $profiles) {
        Write-ModeNative "$output/native/$profile.so" $profile
        @{profile=$profile;native="$profile.so";sha256=(Get-FileHash "$output/native/$profile.so").Hash.ToLowerInvariant()}
    }
    $global:Qt4ModeAbi='arm64-v8a'
    Write-ModeManifest $built
    Complete-ModeGeneration
    Reset-Calls
    Expect-Failure ($arm+@{Mode='package'}) 'Native ABI preflight'
    Assert-Mode (@(Calls).Count -eq 0) 'Wrong ELF bytes reached APK packaging'
    $built=foreach ($profile in $profiles) {
        Write-ModeNative "$output/native/$profile.so" $profile
        @{profile=$profile;native="$profile.so";sha256=(Get-FileHash "$output/native/$profile.so").Hash.ToLowerInvariant()}
    }
    Write-ModeManifest $built
    Complete-ModeGeneration
    Reset-Calls
    Invoke-Mode ($arm+@{Mode='package'})
    $armPackages=@(Get-Content "$output/apk-packages.json" -Raw | ConvertFrom-Json)
    Assert-Mode (@(Calls).Count -eq 12 -and $armPackages.Count -eq 12) 'ARM64 packaging lost a client'
    Assert-Mode (@($armPackages | Where-Object { $_.abi -ne 'arm64-v8a' -or $_.api -ne 21 }).Count -eq 0) 'ARM64 packaging selected the wrong ABI/API'
    Reset-Calls
    Invoke-Mode ($arm+@{Mode='test';RunName='arm-routing';Profiles=@('strict','quick')})
    Assert-Mode (@(Calls).Count -eq 1 -and @(Calls)[0] -eq 'test|arm64-v8a|arm-routing|strict,quick') 'ARM64 test routing lost profiles or compiled code'
    foreach ($busyName in @('qemu-system-armel-headless','qemu-system-aarch64-headless','qemu-system-mips64el')) {
        $global:Qt4ModeBusyProcess=$busyName
        foreach ($busyAbi in @('x86','x86_64','arm64-v8a')) {
            foreach ($busyMode in @('sdk','examples')) {
                Reset-Calls
                $busyOptions=@{}+$entry
                $busyOptions.Abi=$busyAbi;$busyOptions.Mode=$busyMode
                Expect-Failure $busyOptions 'Stop the Android emulator before compiling'
                Assert-Mode (@(Calls).Count -eq 0) "Busy $busyName entered a tool phase for $busyAbi/$busyMode"
            }
        }
    }
    $global:Qt4ModeBusyProcess=''
    Write-Output 'PASS: explicit SDK build, ready-image clients, package/test isolation, stale SDK/native rejection, legacy default preserved'
} finally {
    $env:LONGREACH_MODE_TEST_LOG=$previousLog
    if (Test-Path -LiteralPath $fixture) {
        $resolved=(Resolve-Path -LiteralPath $fixture).Path
        if ([IO.Path]::GetDirectoryName($resolved) -ne $parent -or [IO.Path]::GetFileName($resolved) -notlike 'qt4-android-modes-*') { throw 'Unexpected fixture cleanup path' }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
    Remove-Variable Qt4ModeJobSecrets,Qt4ModeBusyProcess,Qt4ModeAbi,Qt4ModeId,Qt4ModeMissing,Qt4ModeFailPackage,Qt4ModePython,Qt4ModeCacheBusy -Scope Global -ErrorAction SilentlyContinue
}
