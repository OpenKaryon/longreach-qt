# SPDX-License-Identifier: GPL-3.0-or-later
# Actual Qt4 suite/validators with recording host/device boundaries; no guest.
param([string]$RepoRoot=(Resolve-Path "$PSScriptRoot/../../..").Path,
      [ValidateSet('x86','x86_64','arm64-v8a')][string[]]$Abis=@('x86','x86_64','arm64-v8a'))
$ErrorActionPreference='Stop'
$parent=(New-Item -ItemType Directory -Force "$RepoRoot/build/fixtures").FullName
$fixture=Join-Path $parent ('qt4-android-runner-'+[guid]::NewGuid())
$global:Qt4RunnerFixtureRepo=$RepoRoot
$global:Qt4RunnerFixtureHome=$fixture
$global:Qt4RunnerFixturePython=(Get-Command python -CommandType Application | Select-Object -First 1).Source
$global:Qt4RunnerFixtureRoot=''
$global:Qt4RunnerFixtureAbi=''
$global:Qt4RunnerFixtureProfile=''
$global:Qt4RunnerFixtureMarker=''
$global:Qt4RunnerFixtureMutation=''
$global:Qt4RunnerFixtureStopped=$false
$global:Qt4RunnerFixtureReleased=$false
$global:Qt4RunnerFixtureInstrument=$null
$global:Qt4RunnerFixtureCalls=[Collections.Generic.List[string]]::new()
$global:AndroidOwnedFixture=@{Repo=$RepoRoot;Python=$global:Qt4RunnerFixturePython;RecordStart=$true}
function Assert-Qt4Fixture([bool]$Condition,[string]$Message) { if (!$Condition) { throw $Message } }
function Expect-Qt4FixtureFailure([scriptblock]$Action,[string]$Message) {
    try { & $Action } catch { Assert-Qt4Fixture ($_.Exception.Message -match $Message) "Unexpected Qt4 failure: $_"; return }
    throw 'Expected Qt4 runner refusal'
}
function Get-Process { param($Name,$ErrorAction) return $null }
function Start-Sleep { param($Seconds,$Milliseconds) }
function docker {
    Assert-Qt4Fixture ($args[0] -eq 'ps') 'Unexpected container operation in recording fixture'
    $global:Qt4RunnerFixtureCalls.Add('docker-ps-recorded')
    $global:LASTEXITCODE=0
}
function tar.exe {
    $target=$args[[Array]::IndexOf($args,'-C')+1]
    Assert-Qt4Fixture ([IO.Path]::GetFullPath($target) -eq [IO.Path]::GetFullPath("$global:Qt4RunnerFixtureRoot/media")) 'Unexpected synthetic extraction root'
    New-Item -ItemType Directory -Force "$target/x86","$target/tools" | Out-Null
    foreach ($name in @('x86/userdata.img','x86/system.img','x86/kernel-qemu','x86/ramdisk.img','tools/emulator-x86.exe')) {
        [IO.File]::WriteAllText((Join-Path $target $name),'synthetic image/executable data, never executed')
    }
    $global:LASTEXITCODE=0
}
function Start-Process {
    param($FilePath,$ArgumentList,$WindowStyle,[switch]$PassThru,$RedirectStandardOutput,$RedirectStandardError)
    Assert-Qt4Fixture ($WindowStyle -eq 'Hidden') 'Runner requested a visible process window'
    if ($ArgumentList -contains 'instrument') {
        Assert-Qt4Fixture (($ArgumentList[0..3] -join '|') -ceq ('-H|localhost|-P|'+$global:LongreachAndroidAdbContext.Endpoint.port)) 'Instrumentation skipped frozen ADB endpoint'
        $global:Qt4RunnerFixtureCalls.Add('instrument')
        $exitCode=if ($global:Qt4RunnerFixtureMutation -eq 'instrument-exit') { 1 } else { 0 }
        $object=[pscustomobject]@{Id=9124;HasExited=($global:Qt4RunnerFixtureMutation -ne 'instrument-timeout');ExitCode=$exitCode;Disposed=$false}
        [IO.File]::WriteAllText($RedirectStandardOutput,"INSTRUMENTATION_CODE: -1`n")
        $global:Qt4RunnerFixtureInstrument=$object
    } else {
        Assert-Qt4Fixture ([IO.Path]::GetFileName($FilePath) -eq 'emulator-x86.exe') 'Unexpected process requested by Qt4 fixture'
        $global:Qt4RunnerFixtureCalls.Add('emulator-start-recorded')
        $global:Qt4RunnerFixtureStopped=$false
        $object=[pscustomobject]@{Id=9123;HasExited=$false;ExitCode=0;Disposed=$false}
        [IO.File]::WriteAllText($RedirectStandardOutput,'recorded emulator output')
    }
    [IO.File]::WriteAllText($RedirectStandardError,'')
    $object | Add-Member ScriptMethod WaitForExit { param($Milliseconds); return $this.HasExited }
    $object | Add-Member ScriptMethod Dispose { $this.Disposed=$true }
    return $object
}
function Stop-Process { param($InputObject,$ErrorAction); $InputObject.HasExited=$true; $global:Qt4RunnerFixtureCalls.Add('stop-owned-instrument') }
function python {
    $program=[string]$args[0]
    if ([IO.Path]::GetFileName($program) -eq 'prepare-emulator.py') { $global:LASTEXITCODE=0; return }
    $relative=[IO.Path]::GetRelativePath($global:Qt4RunnerFixtureHome,$program)
    $actual=Join-Path $global:Qt4RunnerFixtureRepo $relative
    if ([IO.Path]::GetFileName($program) -in @('android-api21-identity.py','collect-api21-results.py')) {
        & $global:Qt4RunnerFixturePython "$global:Qt4RunnerFixtureHome/data.py" dispatch $actual @($args | Select-Object -Skip 1)
    } else { & $global:Qt4RunnerFixturePython $actual @($args | Select-Object -Skip 1) }
}
try {
    foreach ($relative in @('scripts/run/android/android-adb-endpoint.ps1','scripts/run/android/android-emulator-state.ps1','scripts/run/qt4-android-api21-suite.ps1','scripts/run/android/android-cpu.ps1',
            'scripts/build/android-api21/artifact-lock.ps1')) {
        $destination=Join-Path $fixture $relative
        New-Item -ItemType Directory -Force (Split-Path $destination) | Out-Null
        Copy-Item -LiteralPath (Join-Path $RepoRoot $relative) -Destination $destination
    }
    '. "$($global:AndroidOwnedFixture.Repo)/scripts/tests/android/android-owned-process-mock.ps1"' | Set-Content "$fixture/scripts/run/android/android-owned-process.ps1"
    @'
import importlib.util, pathlib, shutil, sys
def load(path):
    spec = importlib.util.spec_from_file_location('qt4_runner_recording_module', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
action = sys.argv[1]
if action == 'dispatch':
    module = load(sys.argv[2])
    arguments = sys.argv[3:]
    root = pathlib.Path(arguments[arguments.index('--root')+1])
    getattr(module, '_identity', module).REPO = root / 'fixture-media-repo'
    module.main(arguments)
else:
    repo, root = map(pathlib.Path, sys.argv[2:4])
    abi = sys.argv[4]
    sys.path.insert(0, str(repo / 'scripts/tests/android'))
    import android_result_fixtures as fixtures
    if action == 'seed':
        root.mkdir(parents=True, exist_ok=True)
        fixtures.qt4(root, abi)
        shutil.copytree(root / 'fixture-run', root.parent / ('templates-'+abi))
    elif action == 'start':
        fixtures.media_fixtures.launch(root, abi, sys.argv[5])
        launch = fixtures.json.loads((root / sys.argv[5] / 'emulator-launch.json').read_text())
        fixtures.host_fixtures.capture(root / sys.argv[5], launch['emulator'], launch['arguments'], completed=False, artifact_root=root)
    else:
        raise AssertionError(action)
'@ | Set-Content "$fixture/data.py"
    @'
function Invoke-AndroidApi21Adb {
    param($Adb,$Serial,[string[]]$Parameters,[switch]$AllowNonzero)
    $global:Qt4RunnerFixtureCalls.Add($Parameters -join ' ')
    if ($Parameters[0] -eq 'install') {
        $global:Qt4RunnerFixtureProfile=[IO.Path]::GetFileNameWithoutExtension($Parameters[-1])
        $global:Qt4RunnerFixtureReleased=$false
        if ($global:Qt4RunnerFixtureMutation -eq 'install-failure') { return 'Failure [fixture]' }
        if ($global:Qt4RunnerFixtureMutation -eq 'install-timeout') { throw 'ADB command timed out: Qt4 recorded install' }
        if ($global:Qt4RunnerFixtureMutation -eq 'apk-during-install') { [IO.File]::AppendAllText($Parameters[-1],'changed during install') }
        if ($global:Qt4RunnerFixtureMutation -eq 'packages-after-install') { [IO.File]::AppendAllText("$global:Qt4RunnerFixtureRoot/apk-packages.json","`n") }
        return 'Success'
    }
    if ($Parameters[0] -eq 'uninstall') { $global:Qt4RunnerFixtureReleased=$true;return 'Success' }
    if ($Parameters[0] -eq 'logcat') {
        $lines=@("I/LongreachCase( 111): $global:Qt4RunnerFixtureMarker",'I/Probe( 222): QtCore 4.8.7 PASS')
        if ($global:Qt4RunnerFixtureMutation -eq 'debuggerd') { $lines += 'I/DEBUG( 333): *** *** *** *** *** *** *** ***' }
        if ($global:Qt4RunnerFixtureReleased) {
            switch ($global:Qt4RunnerFixtureMutation) {
                'cleanup-case-crash' { $lines+=@('I/DEBUG( 333): *** *** ***') }
                'cleanup-case-lost' { $lines=@($lines[0]) }
                'cleanup-case-query' { throw 'Recorded Qt4 case cleanup log query failed' }
            }
        }
        return $lines
    }
    if ($Parameters[0] -eq 'pull') {
        if ($global:Qt4RunnerFixtureMutation -eq 'pull-failure') { throw 'ADB Qt4 report pull failed: fixture' }
        $source="$global:Qt4RunnerFixtureHome/templates-$global:Qt4RunnerFixtureAbi/$global:Qt4RunnerFixtureProfile/files"
        Copy-Item -LiteralPath $source -Destination $Parameters[-1] -Recurse
        if ($global:Qt4RunnerFixtureMutation -eq 'missing-frame') { [IO.File]::Delete((Join-Path $Parameters[-1] 'qml-gallery.png')) }
        if ($global:Qt4RunnerFixtureMutation -eq 'missing-quick-check') { [IO.File]::WriteAllText((Join-Path $Parameters[-1] 'quick-smoke.txt'),'PASS: qrc and first frame') }
        return 'files pulled'
    }
    if ($Parameters[0] -eq 'shell') {
        switch ($Parameters[1]) {
            'getprop' {
                $api=if ($global:Qt4RunnerFixtureAbi -eq 'x86') { '10' } else { '21' }
                $release=if ($api -eq '10') { '2.3.7' } else { '5.0.2' }
                if ($Parameters.Count -eq 2) { return @("[ro.build.version.sdk]: [$api]","[ro.build.version.release]: [$release]","[ro.product.cpu.abi]: [$global:Qt4RunnerFixtureAbi]") }
                switch ($Parameters[-1]) { 'ro.build.version.sdk' {$api} 'ro.build.version.release' {$release} 'ro.product.cpu.abi' {$global:Qt4RunnerFixtureAbi} }
                return
            }
            'cat' {
                if ($Parameters[-1] -eq '/proc/cpuinfo') { return Get-Content "$global:Qt4RunnerFixtureHome/templates-$global:Qt4RunnerFixtureAbi/guest-cpuinfo.txt" }
                if ($global:Qt4RunnerFixtureProfile -eq 'bootstrap') { return '42' }
                return '0'
            }
            'input' { return }
            'pm' { return 'Success' }
            'log' {
                $global:Qt4RunnerFixtureMarker=$Parameters[-1]
                if ($global:Qt4RunnerFixtureMutation -eq 'generation-after-marker') { [IO.File]::AppendAllText("$global:Qt4RunnerFixtureRoot/apk-manifest.json","`n") }
                return
            }
            'am' {
                if ($Parameters[2] -eq 'force-stop') { return }
                if ($Parameters[2] -eq 'start') { return 'Starting activity' }
            }
        }
    }
    throw ('Unexpected Qt4 recorded ADB command: '+($Parameters -join ' '))
}
'@ | Set-Content "$fixture/scripts/run/android/android-api21-adb.ps1"
    '. "$global:Qt4RunnerFixtureRepo/scripts/run/android/android-api21-log.ps1"' | Set-Content "$fixture/scripts/run/android/android-api21-log.ps1"
    @'
function Wait-AndroidBoot {
    param($Adb,$Serial,$RunDirectory,$EmulatorPid,$TimeoutSeconds,$EmulatorProcess)
    if ($global:Qt4RunnerFixtureMutation -eq 'apk-at-boot') { [IO.File]::AppendAllText("$global:Qt4RunnerFixtureRoot/network.apk",'changed at boot') }
}
'@ | Set-Content "$fixture/scripts/run/android/android-wait-boot.ps1"
    @'
param($OutputDirectory,$Emulator,$RunName,$Gpu,$Abi,[switch]$PassThru)
$global:Qt4RunnerFixtureStopped=$false
& $global:Qt4RunnerFixturePython "$global:Qt4RunnerFixtureHome/data.py" start $global:Qt4RunnerFixtureRepo $OutputDirectory $Abi $RunName
if ($LASTEXITCODE) { throw 'Could not create synthetic Qt4 launch metadata' }
if ($PassThru) { return (Get-AndroidOwnedProcess "$OutputDirectory/$RunName") }
'@ | Set-Content "$fixture/scripts/run/qt6-android-start.ps1"
    @'
param($Adb,$Serial,$RunDirectory,$EmulatorPid,[switch]$RequireFinalLog)
$global:Qt4RunnerFixtureStopped=$true
if (!$RequireFinalLog) { throw 'Qt4 JNI runner did not require final log capture' }
$changed=switch ($global:Qt4RunnerFixtureMutation) {
    'late-packages' {'apk-packages.json'} 'late-generation' {'apk-manifest.json'} 'late-native-generation' {'examples-manifest.json'}
    'late-sdk' {'sdk-image-id.txt'} 'late-apk' {'network.apk'} 'late-unused-apk' {'graphics.apk'} 'late-unused-native' {'native/graphics.so'}
}
if ($changed) { [IO.File]::AppendAllText((Join-Path $global:Qt4RunnerFixtureRoot $changed),[Environment]::NewLine) }
if ($global:Qt4RunnerFixtureMutation -eq 'late-cpu') { [IO.File]::AppendAllText("$RunDirectory/guest-cpuinfo.txt",[Environment]::NewLine) }
if ($global:Qt4RunnerFixtureMutation -eq 'late-identity') { [IO.File]::AppendAllText("$RunDirectory/emulator-identity.json",[Environment]::NewLine) }
. "$($global:AndroidOwnedFixture.Repo)/scripts/tests/android/android-owned-process-mock.ps1"
$control=Get-AndroidOwnedProcess $RunDirectory
try {
    if ($global:Qt4RunnerFixtureMutation -eq 'cleanup-final-query') { throw 'Recorded Qt4 final log capture query failed' }
    $last="$RunDirectory/$global:Qt4RunnerFixtureProfile/logcat-after-cleanup-raw.log"
    $lines=if (Test-Path $last) { @(Get-Content $last) } else { @("I/LongreachCase( 111): $global:Qt4RunnerFixtureMarker",'I/Probe( 222): QtCore 4.8.7 PASS') }
    if ($global:Qt4RunnerFixtureMutation -eq 'cleanup-final-empty') { $lines=@() }
    if (!$lines.Count) { throw 'Recorded Qt4 final log capture is empty' }
    if ($global:Qt4RunnerFixtureMutation -eq 'cleanup-final-crash') { $lines+=@('I/DEBUG( 333): *** *** ***') }
    if ($global:Qt4RunnerFixtureMutation -eq 'cleanup-final-marker') { $lines=@('I/ActivityManager( 111): lost previous capture') }
    $lines | Set-Content "$RunDirectory/final-logcat.log"
    $capture=@{schema_version=1;serial=$Serial;captured=$true;
        host_process_owner_sha256=$control.OwnerSha;host_process_request_sha256=$control.RequestSha;
        logcat_sha256=(Get-FileHash "$RunDirectory/final-logcat.log").Hash.ToLowerInvariant()}
    if ($global:Qt4RunnerFixtureMutation -eq 'cleanup-capture-owner') { $capture.host_process_owner_sha256='0'*64 }
    $capture | ConvertTo-Json -Depth 4 | Set-Content "$RunDirectory/final-logcat-capture.json"
} finally {
    $result=Stop-AndroidOwnedProcess $control
    $control.Process=$null
}
$result
'@ | Set-Content "$fixture/scripts/run/android/android-api21-cleanup.ps1"
    New-Item -ItemType Directory -Force "$fixture/scripts/fetch","$fixture/sdk/platform-tools" | Out-Null
    'param($Scope,$Abi,$AndroidSdk)' | Set-Content "$fixture/scripts/fetch/qt4-android.ps1"
    [IO.File]::WriteAllText("$fixture/sdk/platform-tools/adb.exe",'fixture text, never executed')
    foreach ($script in @(Get-ChildItem "$fixture/scripts" -Recurse -Filter '*.ps1')) {
        $tokens=$null;$errors=$null
        $null=[Management.Automation.Language.Parser]::ParseFile($script.FullName,[ref]$tokens,[ref]$errors)
        if ($errors.Count) { throw "Generated Qt4 fixture $($script.Name): $($errors.Message -join '; ')" }
    }
    $runner="$fixture/scripts/run/qt4-android-api21-suite.ps1"
    $reports=@('final-results.json','final-results-table.md','apk-native-abi-check.json','apk-architecture-final.json','screenshots.json')
    foreach ($abi in $Abis) {
        $global:Qt4RunnerFixtureAbi=$abi
        $global:Qt4RunnerFixtureRoot=Join-Path $fixture $abi
        $root=$global:Qt4RunnerFixtureRoot
        & $global:Qt4RunnerFixturePython "$fixture/data.py" seed $RepoRoot $root $abi
        if ($LASTEXITCODE) { throw 'Could not seed Qt4 APK/native metadata' }
        $entry=@{Abi=$abi;AndroidSdk="$fixture/sdk";OutputDirectory=$root;RunName='full'}
        & $runner @entry | Out-Null
        $final=Get-Content "$root/final-results.json" -Raw | ConvertFrom-Json
        Assert-Qt4Fixture ($final.all_required_passed -and $final.required_cases -eq 12 -and $final.cases.Count -eq 12 -and $global:Qt4RunnerFixtureStopped) 'Qt4 full runner missed cases/collection/cleanup'
        Assert-Qt4Fixture ($global:Qt4RunnerFixtureInstrument.Disposed -and $global:Qt4RunnerFixtureInstrument.HasExited) 'Successful instrumentation handle was not released'
        Assert-Qt4Fixture (@(Get-Content "$root/screenshots.json" -Raw | ConvertFrom-Json).Count -eq 2) 'Full GUI screenshot validation did not run'
        # A direct collector cannot accept a debuggerd signature in matching raw
        # and scoped logs merely because the JNI result file says zero.
        $rawPath="$root/full/network/logcat-raw.log"
        $logPath="$root/full/network/logcat.log"
        $rawBytes=[IO.File]::ReadAllBytes($rawPath);$logBytes=[IO.File]::ReadAllBytes($logPath)
        foreach ($path in @($rawPath,$logPath)) { [IO.File]::AppendAllText($path,"I/DEBUG( 333): *** *** *** *** *** *** *** ***`n") }
        $fatalOutput=@(& $global:Qt4RunnerFixturePython "$fixture/data.py" dispatch "$RepoRoot/scripts/build/qt4-android/collect-api21-results.py" --root $root --run full --abi $abi 2>&1)
        Assert-Qt4Fixture ($LASTEXITCODE -ne 0 -and ($fatalOutput -join "`n") -match 'Fatal cleanup error') 'Qt4 collector accepted debuggerd despite a zero JNI result'
        foreach ($name in $reports) { Assert-Qt4Fixture (!(Test-Path (Join-Path $root $name))) 'Fatal direct collection kept an old aggregate' }
        [IO.File]::WriteAllBytes($rawPath,$rawBytes);[IO.File]::WriteAllBytes($logPath,$logBytes)
        $saved=@{}
        foreach ($name in @('network.apk','graphics.apk','native/graphics.so','apk-packages.json','apk-manifest.json','examples-manifest.json','sdk-image-id.txt')) { $saved[$name]=[IO.File]::ReadAllBytes((Join-Path $root $name)) }
        $mutations=@('apk-at-boot','apk-during-install','packages-after-install','generation-after-marker','late-apk','late-unused-apk','late-unused-native','late-packages','late-generation','late-native-generation','late-sdk','late-cpu','install-failure','pull-failure','debuggerd','install-timeout','cleanup-case-crash','cleanup-case-lost','cleanup-case-query','cleanup-final-query','cleanup-final-empty','cleanup-final-crash','cleanup-final-marker','cleanup-capture-owner')
        if ($abi -ne 'x86') { $mutations += 'late-identity' }
        foreach ($mutation in $mutations) {
            $global:Qt4RunnerFixtureMutation=$mutation
            $global:Qt4RunnerFixtureCalls.Clear()
            foreach ($name in $reports) { [IO.File]::WriteAllText((Join-Path $root $name),'old aggregate PASS') }
            $entry.RunName='failure-'+$mutation;$entry.Profiles=@('network')
            Expect-Qt4FixtureFailure { & $runner @entry | Out-Null } 'Artifact bytes differ|Qt4 APK/native generation changed|Guest CPU evidence changed|APK install failed|ADB Qt4 report pull failed|crashed|ADB command timed out|case cleanup log|final log capture'
            Assert-Qt4Fixture $global:Qt4RunnerFixtureStopped "Failed $mutation skipped owned cleanup"
            foreach ($name in $reports) { Assert-Qt4Fixture (!(Test-Path (Join-Path $root $name))) "Failed $mutation kept $name" }
            if ($mutation -in @('apk-at-boot','apk-during-install','packages-after-install','generation-after-marker','install-failure','install-timeout')) {
                Assert-Qt4Fixture (@($global:Qt4RunnerFixtureCalls | Where-Object { $_ -like 'shell am start *' -or $_ -eq 'instrument' }).Count -eq 0) "Changed $mutation reached launch"
            }
            foreach ($name in $saved.Keys) { [IO.File]::WriteAllBytes((Join-Path $root $name),$saved[$name]) }
        }
        foreach ($mutation in @('instrument-timeout','instrument-exit','missing-frame','missing-quick-check')) {
            $global:Qt4RunnerFixtureMutation=$mutation
            $global:Qt4RunnerFixtureCalls.Clear()
            foreach ($name in $reports) { [IO.File]::WriteAllText((Join-Path $root $name),'old quick aggregate PASS') }
            $entry.RunName='failure-'+$mutation;$entry.Profiles=@('quick')
            Expect-Qt4FixtureFailure { & $runner @entry | Out-Null } 'instrumentation timed out|instrumentation failed|Missing rendered gallery frame|Missing gallery check'
            Assert-Qt4Fixture ($global:Qt4RunnerFixtureStopped -and $global:Qt4RunnerFixtureInstrument.Disposed -and $global:Qt4RunnerFixtureInstrument.HasExited) "Failed $mutation retained its instrumentation client"
            foreach ($name in $reports) { Assert-Qt4Fixture (!(Test-Path (Join-Path $root $name))) "Failed $mutation retained a quick aggregate" }
            if ($mutation -eq 'instrument-timeout') { Assert-Qt4Fixture ($global:Qt4RunnerFixtureCalls.Contains('stop-owned-instrument')) 'Timeout did not stop its retained instrumentation handle' }
        }
        $global:Qt4RunnerFixtureMutation=''
        $entry.RunName='focused';$entry.Profiles=@('network')
        & $runner @entry | Out-Null
        Assert-Qt4Fixture ($global:Qt4RunnerFixtureStopped -and !(Test-Path "$root/final-results.json")) 'Selected Qt4 profile claimed complete final qualification'
        Assert-Qt4Fixture (Test-Path "$root/full/results.json") 'Later Qt4 runs removed prior evidence'
        Write-Output "PASS: actual Qt4 $abi runner, all12 synthetic profiles, generation/install/cleanup refusal, GUI instrumentation ownership and direct fatal-log rejection"
    }
} finally {
    foreach ($name in @('Get-Process','Start-Sleep','Start-Process','Stop-Process','docker','tar.exe','python')) { Remove-Item "Function:$name" -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $fixture) {
        $resolved=(Resolve-Path -LiteralPath $fixture).Path
        if ([IO.Path]::GetDirectoryName($resolved) -ne $parent -or [IO.Path]::GetFileName($resolved) -notlike 'qt4-android-runner-*') { throw 'Unexpected Qt4 runner fixture cleanup path' }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
    Remove-Variable AndroidOwnedFixture,AndroidOwnedMockControls -Scope Global -ErrorAction SilentlyContinue
    Get-Variable -Name 'Qt4RunnerFixture*' -Scope Global | Remove-Variable -Scope Global
}
