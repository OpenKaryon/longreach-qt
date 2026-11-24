# SPDX-License-Identifier: GPL-3.0-or-later
# Real Qt5/Qt6 runner and metadata validators; only external device calls recorded.
param([string]$RepoRoot=(Resolve-Path "$PSScriptRoot/../../..").Path)
$ErrorActionPreference='Stop'
$parent=(New-Item -ItemType Directory -Force "$RepoRoot/build/fixtures").FullName
$fixture=Join-Path $parent ('android-api21-suite-'+[guid]::NewGuid())
$global:Api21FixtureRepo=$RepoRoot
$global:Api21FixtureHome=$fixture
$global:Api21FixturePython=(Get-Command python -CommandType Application | Select-Object -First 1).Source
$global:Api21FixtureCalls=[Collections.Generic.List[string]]::new()
$global:AndroidOwnedFixture=@{Repo=$RepoRoot;Python=$global:Api21FixturePython;RecordStart=$false}
$global:Api21FixtureMutation=''
$global:Api21FixtureStopped=$false
$global:Api21FixtureMarker=''
$global:Api21FixturePackage=''
$global:Api21FixtureCase=''
$global:Api21FixtureApk=''
$global:Api21FixtureRoot=''
$global:Api21FixtureQt=0
$global:Api21FixtureAbi='x86_64'
$global:Api21FixtureForward=$false
$global:Api21FixtureTemplateDirectory=''
$global:Api21FixturePolls=0
function Assert-Suite([bool]$Condition,[string]$Message) { if (!$Condition) { throw $Message } }
function Expect-SuiteFailure([scriptblock]$Action,[string]$Message) {
    try { & $Action } catch { Assert-Suite ($_.Exception.Message -match $Message) "Unexpected API21 failure: $_"; return }
    throw 'Expected API21 runner refusal'
}
function Get-Process { param($Name,$ErrorAction) return $null }
function Start-Sleep { param($Seconds,$Milliseconds) }
function python {
    $program=[string]$args[0]
    # Preparation is replaced by tiny synthetic media in the recorded starter.
    if ([IO.Path]::GetFileName($program) -eq 'prepare-emulator.py') { $global:LASTEXITCODE=0; return }
    $relative=[IO.Path]::GetRelativePath($global:Api21FixtureHome,$program)
    $actual=Join-Path $global:Api21FixtureRepo $relative
    if ([IO.Path]::GetFileName($program) -eq 'android-api21-forward.py') { $global:Api21FixtureCalls.Add('forward-collector') }
    if ([IO.Path]::GetFileName($program) -eq 'android-api21-sound-cache.py') { $global:Api21FixtureCalls.Add('sound-collector') }
    if ([IO.Path]::GetFileName($program) -eq 'collect-results.py') { $global:Api21FixtureCalls.Add('full-collector') }
    if ([IO.Path]::GetFileName($program) -eq 'android-api21-exit.py') { $global:Api21FixtureCalls.Add('exit-verifier') }
    if ([IO.Path]::GetFileName($program) -in @('android-api21-identity.py','collect-results.py','android-api21-sound-cache.py','android-api21-forward.py')) {
        & $global:Api21FixturePython "$global:Api21FixtureHome/data.py" dispatch $actual @($args | Select-Object -Skip 1)
    } else {
        & $global:Api21FixturePython $actual @($args | Select-Object -Skip 1)
    }
}
try {
    foreach ($relative in @('scripts/run/android/android-adb-endpoint.ps1','scripts/run/android/android-shell.ps1','scripts/run/android/android-shell-status.ps1','scripts/run/android/android-emulator-state.ps1','scripts/run/android-api21-suite.ps1','scripts/run/android/android-cpu.ps1',
            'scripts/build/android-api21/artifact-lock.ps1','scripts/run/android/android-baselines.json','tests/expected-apps.txt')) {
        $target=Join-Path $fixture $relative
        New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
        Copy-Item -LiteralPath (Join-Path $RepoRoot $relative) -Destination $target
    }
    '. "$($global:AndroidOwnedFixture.Repo)/scripts/tests/android/android-owned-process-mock.ps1"' | Set-Content "$fixture/scripts/run/android/android-owned-process.ps1"
    @'
import importlib.util, pathlib, sys
def load(path):
    spec = importlib.util.spec_from_file_location('api21_recording_module', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
action = sys.argv[1]
if action == 'dispatch':
    module = load(sys.argv[2])
    arguments = sys.argv[3:]
    root = pathlib.Path(arguments[arguments.index('--root')+1])
    identity = getattr(module, '_identity', module)
    identity.REPO = root / 'fixture-media-repo'
    module.main(arguments)
else:
    repo, root = map(pathlib.Path, sys.argv[2:4])
    qt = int(sys.argv[4])
    sys.path.insert(0, str(repo / 'scripts/tests/android'))
    import android_result_fixtures as fixtures
    if action in ('seed', 'seed-full-abi'):
        abi = sys.argv[5] if action == 'seed-full-abi' else 'x86_64'
        root.mkdir(parents=True, exist_ok=True)
        artifacts = load(repo / 'scripts/build/android-api21/artifact-manifest.py')
        fixtures.packaged(root, qt, artifacts, abi)
        names = ['strict-cxx23', *artifacts.APPS, 'widgets-gui', 'qml-gui']
        if qt == 5:
            names += ['strict-cxx23-extended', 'qt-selftest-extended']
        templates = root.parent / (('templates-full-'+str(qt)+'-'+abi) if action == 'seed-full-abi' else ('templates-'+str(qt)))
        templates.mkdir()
        for name in names:
            (templates / (name+'.txt')).write_text(fixtures.stdout(qt,21,abi,name))
    elif action == 'seed-forward':
        abi = sys.argv[5]
        root.mkdir(parents=True, exist_ok=True)
        artifacts = load(repo / 'scripts/build/android-api21/artifact-manifest.py')
        fixtures.packaged(root, 5, artifacts, abi)
        templates = root.parents[1] / ('templates-forward-'+abi)
        templates.mkdir()
        (templates / 'api10-selftest.txt').write_text(fixtures.stdout(5,10,abi,'qt-selftest'))
    elif action == 'seed-sound':
        abi = sys.argv[5]
        root.mkdir(parents=True, exist_ok=True)
        artifacts = load(repo / 'scripts/build/android-api21/artifact-manifest.py')
        fixtures.packaged(root, qt, artifacts, abi)
        templates = root.parent / ('templates-sound-'+abi)
        templates.mkdir()
        phases = ['SOUND_CACHE: protocol=1','SOUND_CACHE: wav=pcm-s16le-8000-mono',
                  'SOUND_CACHE: ready=1','SOUND_CACHE: playing=1','SOUND_CACHE: destroyed=1','SOUND_CACHE: return=0']
        (templates / 'sound-cache-teardown.txt').write_text('\n'.join(phases))
    elif action == 'start':
        fixtures.media_fixtures.launch(root, sys.argv[6], sys.argv[5])
        launch = fixtures.json.loads((root / sys.argv[5] / 'emulator-launch.json').read_text())
        fixtures.host_fixtures.capture(root / sys.argv[5], launch['emulator'], launch['arguments'], completed=False, artifact_root=root)
    else:
        raise AssertionError(action)
'@ | Set-Content "$fixture/data.py"
    @'
function Invoke-AndroidApi21Adb {
    param($Adb,$Serial,[string[]]$Parameters,[switch]$AllowNonzero)
    if ($Parameters -contains 'reconnect') { throw 'Fixture: suite must not reset global ADB transports' }
    $global:Api21FixtureCalls.Add($Parameters -join ' ')
    if ($Parameters[0] -eq 'install') {
        $global:Api21FixtureApk=$Parameters[-1]
        if ($global:Api21FixtureMutation -eq 'install-failure') { return 'Failure [fixture]' }
        if ($global:Api21FixtureMutation -eq 'install-timeout') { throw 'ADB command timed out: recorded install' }
        if ($global:Api21FixtureMutation -eq 'apk-during-install') { [IO.File]::AppendAllText($Parameters[-1],'changed during install') }
        if ($global:Api21FixtureMutation -eq 'manifest-after-install') { [IO.File]::AppendAllText("$global:Api21FixtureRoot/apk-manifest.json","`n") }
        return 'Success'
    }
    if ($Parameters[0] -eq 'uninstall') { return 'Success' }
    if ($Parameters[0] -in @('start-server','reconnect')) { return }
    if ($Parameters[0] -eq 'logcat') { return @(Get-FixtureExitLog | Select-Object -First 2) }
    if ($Parameters[0] -eq 'pull') {
        if ($global:Api21FixtureMutation -eq 'pull-failure') { throw 'ADB report pull failed: fixture' }
        $target=$Parameters[-1]
        New-Item -ItemType Directory -Force $target | Out-Null
        if ($global:Api21FixtureCase -eq 'sound-cache-teardown') {
            $lines=@(Get-Content "$global:Api21FixtureHome/templates-sound-$global:Api21FixtureAbi/sound-cache-teardown.txt")
            switch ($global:Api21FixtureMutation) {
                'sound-old-output' { $lines=@('---- qt-selftest: 106 passed, 0 failed, 4 skipped ----') }
                'sound-missing-destroy' { $lines=@($lines | Where-Object { $_ -cne 'SOUND_CACHE: destroyed=1' }) }
                'sound-duplicate-return' { $lines+='SOUND_CACHE: return=0' }
                'sound-explicit-failure' { $lines+='FAIL: local sample did not become Ready' }
            }
            $lines | Set-Content "$target/selftest.stdout"
        } else {
            $templates=if ($global:Api21FixtureTemplateDirectory) { $global:Api21FixtureTemplateDirectory } else { "$global:Api21FixtureHome/templates-$global:Api21FixtureQt" }
            Copy-Item -LiteralPath "$templates/$global:Api21FixtureCase.txt" -Destination "$target/selftest.stdout"
            if ($global:Api21FixtureMutation -eq 'forward-low-count') {
                $text=[IO.File]::ReadAllText("$target/selftest.stdout").Replace('213 passed','212 passed')
                [IO.File]::WriteAllText("$target/selftest.stdout",$text)
            }
            if ($global:Api21FixtureMutation -eq 'forward-missing-timing') {
                $text=[IO.File]::ReadAllText("$target/selftest.stdout").Replace('elapsed_ms=250','elapsed_ms=0')
                [IO.File]::WriteAllText("$target/selftest.stdout",$text)
            }
        }
        [IO.File]::WriteAllText("$target/selftest-result.txt",'0')
        return 'files pulled'
    }
    if ($Parameters.Count -eq 2 -and $Parameters[0] -eq 'shell' -and $Parameters[1] -match 'LONGREACH_SHELL_[a-f0-9]{32}') {
        $status=$Matches[0]
        if ($Parameters[1] -match 'LongreachCase (BEGIN-[a-f0-9]+)') {
            $global:Api21FixtureMarker=$Matches[1]
            if ($global:Api21FixtureMutation -eq 'manifest-after-marker') { [IO.File]::AppendAllText("$global:Api21FixtureRoot/apk-manifest.json","`n") }
        }
        return "${status}:0"
    }
    if ($Parameters[0] -eq 'shell') {
        switch ($Parameters[1]) {
            'getprop' {
                if ($Parameters.Count -eq 2) { return @('[ro.build.version.release]: [5.0.2]','[ro.build.version.sdk]: [21]',"[ro.product.cpu.abi]: [$global:Api21FixtureAbi]") }
                switch ($Parameters[-1]) { 'ro.build.version.release' {'5.0.2'} 'ro.build.version.sdk' {'21'} 'ro.product.cpu.abi' {$global:Api21FixtureAbi} }
                return
            }
            'cat' {
                if ($Parameters[-1] -eq '/proc/cpuinfo') {
                    if ($global:Api21FixtureAbi -eq 'x86_64') { return @('processor: 0','flags: cx16 lahf_lm pni popcnt ssse3 sse4_1 sse4_2') }
                    if ($global:Api21FixtureAbi -eq 'x86') { return @('processor: 0','flags: ssse3') }
                    return @('Processor: synthetic ARM metadata','Hardware: fixture')
                }
                $global:Api21FixturePolls++
                if ($global:Api21FixturePolls -eq 1) { return } # exercise incomplete poll/log branch
                return '0'
            }
            'input' { return }
            'pm' { return 'Success' }
            'log' {
                $global:Api21FixtureMarker=$Parameters[-1]
                if ($global:Api21FixtureMutation -eq 'manifest-after-marker') { [IO.File]::AppendAllText("$global:Api21FixtureRoot/apk-manifest.json","`n") }
                return
            }
            'am' {
                if ($Parameters[2] -eq 'force-stop') { return }
                if ($Parameters[2] -eq 'start') {
                    $global:Api21FixturePackage=$Parameters[[Array]::IndexOf($Parameters,'-n')+1].Split('/')[0]
                    $app=[IO.Path]::GetFileNameWithoutExtension($global:Api21FixtureApk)
                    $extended=$global:Api21FixtureApk.Replace('\','/').Contains('/extended/')
                    $argument=$Parameters[[Array]::IndexOf($Parameters,'applicationArguments')+1]
                    $global:Api21FixtureCase=if ($global:Api21FixtureForward) { 'api10-selftest' }
                        elseif ($argument -eq '--sound-cache-teardown') { 'sound-cache-teardown' }
                        elseif ($argument -eq '--modern-cpp') { if ($extended) { 'strict-cxx23-extended' } else { 'strict-cxx23' } }
                        elseif ($argument -eq '--gallery-selftest') { if ($app -eq 'widgets-gallery') { 'widgets-gui' } else { 'qml-gui' } }
                        elseif ($extended) { 'qt-selftest-extended' } else { $app }
                    $global:Api21FixturePolls=0
                    return 'Starting activity'
                }
            }
        }
    }
    throw ('Unexpected recorded API21 command: '+($Parameters -join ' '))
}
function Get-FixtureExitLog {
    param([switch]$AfterCleanup,[switch]$Final)
    $lines=@("I/LongreachCase( 123): $global:Api21FixtureMarker",
        "I/ActivityManager( 60): Start proc $global:Api21FixturePackage for activity $global:Api21FixturePackage/.Activity: pid=1234 uid=10001 gids={}")
    if ($global:Api21FixtureMutation -eq 'sound-early-fatal') { $lines+='E/AndroidRuntime(1234): FATAL EXCEPTION: main' }
    if (($AfterCleanup -and $global:Api21FixtureMutation -eq 'normal-case-debuggerd') -or
            ($Final -and $global:Api21FixtureMutation -eq 'normal-final-debuggerd')) {
        $lines+='I/DEBUG(99): *** *** ***'
        $lines+="I/DEBUG(99): pid: 1234, tid: 1234 >>> $global:Api21FixturePackage <<<"
    }
    $lines+="I/ActivityManager( 60): Process $global:Api21FixturePackage (pid 1234) has died."
    return $lines
}
'@ | Set-Content "$fixture/scripts/run/android/android-api21-adb.ps1"
    @'
. "$global:Api21FixtureRepo/scripts/run/android/android-api21-log.ps1"
'@ | Set-Content "$fixture/scripts/run/android/android-api21-log.ps1"
    @'
. "$global:Api21FixtureRepo/scripts/run/android/android-process-exit.ps1"
function Invoke-AndroidExitQuery {
    param($Adb,$Serial,[string[]]$Command,$Directory,$Name,$TimeoutMilliseconds,[switch]$AllowNonzero)
    if ($Command[0] -eq 'logcat') { return (Get-FixtureExitLog -AfterCleanup:($Name -eq 'case-cleanup-logcat')) }
    if ($Command[0] -eq 'shell' -and $Command[1] -eq 'ps') { return @('USER PID PPID NAME','root 1 0 /init') }
    throw 'Unexpected recorded API21 exit query'
}
'@ | Set-Content "$fixture/scripts/run/android/android-process-exit.ps1"
    @'
function Wait-AndroidBoot {
    param($Adb,$Serial,$RunDirectory,$EmulatorPid,$EmulatorProcess)
    if ($global:Api21FixtureMutation -eq 'apk-at-boot') { [IO.File]::AppendAllText("$global:Api21FixtureRoot/apk/network-gui.apk",'changed at boot') }
}
'@ | Set-Content "$fixture/scripts/run/android/android-wait-boot.ps1"
    @'
param($OutputDirectory,$Emulator,$RunName,$Gpu,$Abi,[switch]$PassThru)
$global:Api21FixtureStopped=$false
& $global:Api21FixturePython "$global:Api21FixtureHome/data.py" start $global:Api21FixtureRepo $OutputDirectory $global:Api21FixtureQt $RunName $Abi
if ($LASTEXITCODE) { throw 'Synthetic media preparation failed' }
if ($PassThru) { return (Get-AndroidOwnedProcess "$OutputDirectory/$RunName") }
'@ | Set-Content "$fixture/scripts/run/qt6-android-start.ps1"
    @'
param($Adb,$Serial,$RunDirectory,$EmulatorPid,[switch]$RequireFinalLog)
$global:Api21FixtureStopped=$true
if ($RequireFinalLog) {
    $owner=Get-AndroidOwnedProcess $RunDirectory
    $lines=@(Get-FixtureExitLog -Final)
    if ($global:Api21FixtureMutation -eq 'sound-late-debuggerd') {
        $lines+='I/DEBUG(99): *** *** ***'
        $lines+="I/DEBUG(99): pid: 1234, tid: 1234 >>> $global:Api21FixturePackage <<<"
        $lines+='I/DEBUG(99): signal 11 (SIGSEGV)'
    }
    $lines | Set-Content "$RunDirectory/final-logcat.log"
    $capture=@{schema_version=1;captured=$true;serial=$Serial;
        host_process_owner_sha256=$owner.OwnerSha;host_process_request_sha256=$owner.RequestSha;
        logcat_sha256=(Get-FileHash "$RunDirectory/final-logcat.log").Hash.ToLowerInvariant()}
    if ($global:Api21FixtureMutation -in @('sound-capture-owner','normal-capture-owner')) { $capture.host_process_owner_sha256='0'*64 }
    $capture | ConvertTo-Json | Set-Content "$RunDirectory/final-logcat-capture.json"
    if ($global:Api21FixtureMutation -eq 'sound-late-stdout') {
        [IO.File]::AppendAllText("$RunDirectory/sound-cache-teardown/files/selftest.stdout", "`nSOUND_CACHE: return=0`n")
    }
    if ($global:Api21FixtureMutation -eq 'normal-late-stdout') {
        [IO.File]::AppendAllText("$RunDirectory/$global:Api21FixtureCase/files/selftest.stdout", "`nlate fixture replacement`n")
    }
}
if ($global:Api21FixtureMutation -eq 'late-manifest') { [IO.File]::AppendAllText("$global:Api21FixtureRoot/apk-manifest.json","`n") }
if ($global:Api21FixtureMutation -eq 'late-apk') { [IO.File]::AppendAllText($global:Api21FixtureApk,'changed at cleanup') }
if ($global:Api21FixtureMutation -eq 'late-unused-apk') { [IO.File]::AppendAllText("$global:Api21FixtureRoot/apk/graphics-gallery.apk",'changed unselected APK') }
if ($global:Api21FixtureMutation -eq 'forward-late-policy') { [IO.File]::AppendAllText("$global:Api21FixtureHome/scripts/run/android/android-baselines.json","`n") }
if ($global:Api21FixtureMutation -eq 'late-options') { [IO.File]::AppendAllText("$RunDirectory/run-options.json","`n") }
if ($global:Api21FixtureMutation -eq 'late-launch') { [IO.File]::AppendAllText("$RunDirectory/emulator-launch.json","`n") }
if ($global:Api21FixtureMutation -eq 'late-cpu') { [IO.File]::AppendAllText("$RunDirectory/guest-cpuinfo.txt","`n") }
if ($global:Api21FixtureMutation -eq 'late-host-owner') {
    $path=Join-Path $RunDirectory 'host-process-owner.json'
    $owner=Get-Content $path -Raw | ConvertFrom-Json
    $owner.supervisor_creation_filetime='124'
    $owner | ConvertTo-Json | Set-Content $path
}
. "$($global:AndroidOwnedFixture.Repo)/scripts/tests/android/android-owned-process-mock.ps1"
$proof=Stop-AndroidOwnedProcess (Get-AndroidOwnedProcess $RunDirectory)
if ($RequireFinalLog -and $global:Api21FixtureMutation -eq 'normal-capture-failure') { throw 'Required final Android log capture failed; owned tree was stopped' }
$proof
'@ | Set-Content "$fixture/scripts/run/android/android-api21-cleanup.ps1"
    New-Item -ItemType Directory -Force "$fixture/scripts/fetch","$fixture/sdk" | Out-Null
    'param($AndroidSdk,$Scope,$Abi)' | Set-Content "$fixture/scripts/fetch/qt6-android.ps1"
    foreach ($script in @(Get-ChildItem "$fixture/scripts" -Recurse -Filter '*.ps1')) {
        $tokens=$null;$errors=$null
        $null=[Management.Automation.Language.Parser]::ParseFile($script.FullName,[ref]$tokens,[ref]$errors)
        if ($errors.Count) { throw "Generated fixture $($script.Name): $($errors.Message -join '; ')" }
    }
    $runner="$fixture/scripts/run/android-api21-suite.ps1"
    $reports=@('final-results.json','final-results-table.md','apk-native-abi-check.json','apk-architecture-final.json','screenshots.json')
    foreach ($qt in @(5,6)) {
        $global:Api21FixtureQt=$qt
        $global:Api21FixtureRoot=Join-Path $fixture "qt$qt"
        $root=$global:Api21FixtureRoot
        & $global:Api21FixturePython "$fixture/data.py" seed $RepoRoot $root $qt
        if ($LASTEXITCODE) { throw 'Could not seed API21 metadata' }
        $entry=@{QtMajor=$qt;Abi='x86_64';AndroidSdk="$fixture/sdk";OutputDirectory=$root;RunName='full'}
        & $runner @entry | Out-Null
        $final=Get-Content "$root/final-results.json" -Raw | ConvertFrom-Json
        $results=@(Get-Content "$root/full/results.json" -Raw | ConvertFrom-Json)
        Assert-Suite ($results.Count -eq $(if ($qt -eq 5) {13} else {11})) 'Real runner missed required cases'
        Assert-Suite ($global:Api21FixtureStopped -and $null -ne $final) 'Full synthetic suite skipped cleanup/publication'
        Assert-Suite ($final.all_required_passed -and $final.all_process_exits_confirmed -and $final.qualification -and $final.required_cases -eq $results.Count) 'Synthetic full report lost its required coverage/default classification'
        Assert-Suite (@($results | Where-Object { !$_.process_exit_confirmed -or !$_.apk_manifest_sha256 }).Count -eq 0) 'Real runner lost exit/APK identity'
        $apk="$root/apk/network-gui.apk"
        $other="$root/apk/graphics-gallery.apk"
        $apkBytes=[IO.File]::ReadAllBytes($apk)
        $otherBytes=[IO.File]::ReadAllBytes($other)
        $manifestBytes=[IO.File]::ReadAllBytes("$root/apk-manifest.json")
        foreach ($mutation in @('apk-at-boot','apk-during-install','manifest-after-install','late-apk','late-manifest','late-unused-apk','install-failure','manifest-after-marker','late-options','late-launch','late-cpu','pull-failure','late-host-owner','install-timeout')) {
            $global:Api21FixtureMutation=$mutation
            $global:Api21FixtureCalls.Clear()
            foreach ($name in $reports) { [IO.File]::WriteAllText((Join-Path $root $name),'old aggregate PASS') }
            $entry.RunName='failure-'+$mutation
            $entry.CaseNames=@('network-gui')
            Expect-SuiteFailure { & $runner @entry | Out-Null } 'Artifact bytes differ|APK generation changed|APK install failed|CPU evidence changed|ADB report pull failed|Owned process tree changed|ADB command timed out'
            Assert-Suite $global:Api21FixtureStopped "Failed $mutation did not enter owned cleanup"
            foreach ($name in $reports) { Assert-Suite (!(Test-Path -LiteralPath (Join-Path $root $name))) "Failed $mutation kept $name" }
            if ($mutation -in @('apk-at-boot','apk-during-install','manifest-after-install','manifest-after-marker','install-failure','install-timeout')) {
                Assert-Suite (@($global:Api21FixtureCalls | Where-Object { $_ -like 'shell am start *' }).Count -eq 0) "Changed $mutation reached launch"
            }
            [IO.File]::WriteAllBytes($apk,$apkBytes)
            [IO.File]::WriteAllBytes($other,$otherBytes)
            [IO.File]::WriteAllBytes("$root/apk-manifest.json",$manifestBytes)
        }
        $global:Api21FixtureMutation=''
        $entry.RunName='focused'
        & $runner @entry | Out-Null
        Assert-Suite ($global:Api21FixtureStopped -and !(Test-Path "$root/final-results.json")) 'Focused case claimed full-suite publication'
        Assert-Suite (Test-Path "$root/full/results.json") 'Later refusal destroyed prior full-run evidence'
    }
    foreach ($abi in @('armeabi-v7a','arm64-v8a','x86','x86_64')) {
        $global:Api21FixtureQt=5;$global:Api21FixtureAbi=$abi;$global:Api21FixtureMutation=''
        $global:Api21FixtureRoot=Join-Path $fixture "sound-$abi"
        $root=$global:Api21FixtureRoot
        & $global:Api21FixturePython "$fixture/data.py" seed-sound $RepoRoot $root 5 $abi
        if ($LASTEXITCODE) { throw 'Could not seed API21 sound metadata' }
        $entry=@{QtMajor=5;Abi=$abi;AndroidSdk="$fixture/sdk";OutputDirectory=$root;RunName='sound-good';SoundCacheTeardown=$true}
        $global:Api21FixtureCalls.Clear()
        & $runner @entry | Out-Null
        $diagnostic=Get-Content "$root/sound-good/sound-cache-result.json" -Raw | ConvertFrom-Json
        Assert-Suite ($diagnostic.completed -and !$diagnostic.qualification -and $diagnostic.api -eq 21 -and $diagnostic.abi -ceq $abi -and $diagnostic.cases.Count -eq 1) 'Sound route lost explicit single-case classification'
        Assert-Suite ($diagnostic.cases[0].apk_relative -ceq 'apk/extended/qt-selftest.apk' -and
            $diagnostic.cases[0].arguments -ceq '--sound-cache-teardown') 'Sound route used core APK or normal arguments'
        Assert-Suite ($global:Api21FixtureStopped -and $global:Api21FixtureCalls.Contains('sound-collector') -and !$global:Api21FixtureCalls.Contains('full-collector')) 'Sound route bypassed cleanup or used full-suite collector'
        foreach ($name in $reports) { Assert-Suite (!(Test-Path (Join-Path $root $name))) "Sound route published full-suite $name" }
        $saved=[IO.File]::ReadAllText("$root/sound-good/sound-cache-result.json")
        [IO.File]::WriteAllText("$root/final-results.json",'preserve this preflight sentinel')
        $global:Api21FixtureCalls.Clear()
        Expect-SuiteFailure { & $runner @entry | Out-Null } 'run already exists'
        Assert-Suite ($global:Api21FixtureCalls.Count -eq 0 -and [IO.File]::ReadAllText("$root/sound-good/sound-cache-result.json") -ceq $saved -and
            [IO.File]::ReadAllText("$root/final-results.json") -ceq 'preserve this preflight sentinel') 'Existing sound preflight changed prior evidence'
        foreach ($fault in @('sound-old-output','sound-missing-destroy','sound-duplicate-return','sound-explicit-failure',
                'sound-early-fatal','sound-late-debuggerd','sound-late-stdout','sound-capture-owner')) {
            $global:Api21FixtureMutation=$fault;$global:Api21FixtureStopped=$false
            $entry.RunName=$fault
            Expect-SuiteFailure { & $runner @entry | Out-Null } 'Sound-cache pre-exit protocol failed|Fatal cleanup error|Artifact bytes differ|API21 (sound diagnostic evidence|post-cleanup termination evidence) is incomplete'
            Assert-Suite ($global:Api21FixtureStopped -and !(Test-Path "$root/$fault/sound-cache-result.json")) "Failed $fault sound route retained result or bypassed cleanup"
            foreach ($name in $reports) { Assert-Suite (!(Test-Path (Join-Path $root $name))) "Failed sound $fault kept full-suite $name" }
        }
        $global:Api21FixtureMutation=''
        $global:Api21FixtureCalls.Clear()
        $bad=@{}+$entry;$bad.RunName='unsupported-qt6';$bad.QtMajor=6
        Expect-SuiteFailure { & $runner @bad | Out-Null } 'requires QtMajor 5'
        $bad=@{}+$entry;$bad.RunName='mixed-case';$bad.CaseNames=@('network-gui')
        Expect-SuiteFailure { & $runner @bad | Out-Null } 'cannot be combined with CaseNames'
        Assert-Suite ($global:Api21FixtureCalls.Count -eq 0 -and !(Test-Path "$root/unsupported-qt6") -and !(Test-Path "$root/mixed-case")) 'Unsupported sound mode reached metadata/device calls'
    }
    foreach ($abi in @('armeabi-v7a','x86')) {
        $global:Api21FixtureQt=5;$global:Api21FixtureAbi=$abi;$global:Api21FixtureForward=$true;$global:Api21FixtureMutation=''
        $suffix=if ($abi -eq 'x86') { '-x86' } else { '' }
        $global:Api21FixtureRoot=Join-Path $fixture "artifacts/qt5-android-gingerbread$suffix"
        $root=$global:Api21FixtureRoot
        & $global:Api21FixturePython "$fixture/data.py" seed-forward $RepoRoot $root 5 $abi
        if ($LASTEXITCODE) { throw 'Could not seed forward diagnostic APK metadata' }
        $global:Api21FixtureTemplateDirectory="$fixture/templates-forward-$abi"
        # Omit OutputDirectory: the diagnostic must use the API10 producer's root.
        $entry=@{QtMajor=5;Abi=$abi;AndroidSdk="$fixture/sdk";RunName='forward-good';Api10Compatibility=$true}
        $global:Api21FixtureCalls.Clear()
        & $runner @entry | Out-Null
        $report=Get-Content "$root/forward-good/api10-on-api21-result.json" -Raw | ConvertFrom-Json
        Assert-Suite ($report.completed -and !$report.qualification -and $report.source_api -eq 10 -and
            $report.guest_api -eq 21 -and $report.coverage_api -eq 10 -and $report.cases.Count -eq 1) 'Forward route relabelled the SDK or claimed qualification'
        Assert-Suite ($report.cases[0].apk_relative -ceq 'apk/qt-selftest.apk' -and $report.cases[0].arguments -ceq '--selftest' -and
            $report.cases[0].name -ceq 'api10-selftest' -and $report.all_observed_exits_clean) 'Forward route lost selftest/termination binding'
        Assert-Suite ($global:Api21FixtureStopped -and $global:Api21FixtureCalls.Contains('forward-collector') -and
            $global:Api21FixtureCalls.Contains('exit-verifier') -and !$global:Api21FixtureCalls.Contains('full-collector') -and
            !$global:Api21FixtureCalls.Contains('sound-collector')) 'Forward route used a wrong collector or bypassed cleanup'
        foreach ($name in $reports) { Assert-Suite (!(Test-Path (Join-Path $root $name))) "Forward route published $name" }
        $saved=[IO.File]::ReadAllText("$root/forward-good/api10-on-api21-result.json")
        [IO.File]::WriteAllText("$root/final-results.json",'preflight sentinel')
        $global:Api21FixtureCalls.Clear()
        Expect-SuiteFailure { & $runner @entry | Out-Null } 'run already exists'
        Assert-Suite ($global:Api21FixtureCalls.Count -eq 0 -and [IO.File]::ReadAllText("$root/forward-good/api10-on-api21-result.json") -ceq $saved -and
            [IO.File]::ReadAllText("$root/final-results.json") -ceq 'preflight sentinel') 'Forward reuse preflight changed prior evidence'
        foreach ($kind in @('qt6','abi64','cases','sound','name')) {
            $bad=@{}+$entry;$bad.RunName='bad-'+$kind
            switch ($kind) {
                'qt6' { $bad.QtMajor=6 }
                'abi64' { $bad.Abi='x86_64' }
                'cases' { $bad.CaseNames=@('qt-selftest') }
                'sound' { $bad.SoundCacheTeardown=$true }
                'name' { $bad.RunName='../outside' }
            }
            Expect-SuiteFailure { & $runner @bad | Out-Null } 'requires QtMajor 5|cannot be combined|Invalid API10'
            Assert-Suite ($global:Api21FixtureCalls.Count -eq 0) 'Invalid compatibility request reached metadata/device tools'
        }
        $manifest=[IO.File]::ReadAllBytes("$root/apk-manifest.json")
        $unused=[IO.File]::ReadAllBytes("$root/apk/graphics-gallery.apk")
        $policy=[IO.File]::ReadAllBytes("$fixture/scripts/run/android/android-baselines.json")
        foreach ($fault in @('forward-low-count','forward-missing-timing','normal-case-debuggerd','normal-final-debuggerd',
                'normal-capture-owner','normal-capture-failure','normal-late-stdout','late-manifest','late-unused-apk','forward-late-policy')) {
            $global:Api21FixtureMutation=$fault;$global:Api21FixtureStopped=$false;$global:Api21FixtureCalls.Clear()
            $entry.RunName=$fault
            Expect-SuiteFailure { & $runner @entry | Out-Null } 'Coverage regression|Fatal cleanup error|API21 post-cleanup termination evidence is incomplete|Required final Android log capture failed|Artifact bytes differ|APK generation changed'
            Assert-Suite ($global:Api21FixtureStopped -and !(Test-Path "$root/$fault/api10-on-api21-result.json") -and
                !(Test-Path "$root/final-results.json")) "Failed forward $fault retained current success or bypassed cleanup"
            [IO.File]::WriteAllBytes("$root/apk-manifest.json",$manifest)
            [IO.File]::WriteAllBytes("$root/apk/graphics-gallery.apk",$unused)
            [IO.File]::WriteAllBytes("$fixture/scripts/run/android/android-baselines.json",$policy)
        }
    }
    $global:Api21FixtureForward=$false;$global:Api21FixtureMutation=''
    # Full and selected ordinary modes must use the same final/cleanup gate.
    foreach ($qt in @(5,6)) {
        $ordinaryAbis=if ($qt -eq 5) { @('arm64-v8a','x86_64') } else { @('armeabi-v7a','arm64-v8a','x86','x86_64') }
        foreach ($abi in $ordinaryAbis) {
            $global:Api21FixtureQt=$qt;$global:Api21FixtureAbi=$abi;$global:Api21FixtureMutation=''
            $global:Api21FixtureRoot=Join-Path $fixture "normal-$qt-$abi"
            $root=$global:Api21FixtureRoot
            & $global:Api21FixturePython "$fixture/data.py" seed-full-abi $RepoRoot $root $qt $abi
            if ($LASTEXITCODE) { throw 'Could not seed ordinary all-ABI generation' }
            $global:Api21FixtureTemplateDirectory="$fixture/templates-full-$qt-$abi"
            $entry=@{QtMajor=$qt;Abi=$abi;AndroidSdk="$fixture/sdk";OutputDirectory=$root;RunName='full-cleanup'}
            $global:Api21FixtureCalls.Clear()
            & $runner @entry | Out-Null
            $final=Get-Content "$root/full-cleanup/../final-results.json" -Raw | ConvertFrom-Json
            Assert-Suite ($final.required_cases -eq $(if ($qt -eq 5) {13} else {11}) -and $final.qualification -and
                $final.all_observed_exits_clean -and $final.case_cleanup_evidence.Count -eq $final.required_cases) 'Ordinary full cleanup changed named coverage or omitted observations'
            Assert-Suite ($global:Api21FixtureCalls.Contains('exit-verifier') -and $global:Api21FixtureStopped) 'Full ordinary mode bypassed shared exit verifier/cleanup'
            $entry.CaseNames=@('network-gui');$entry.RunName='selected-cleanup'
            $global:Api21FixtureCalls.Clear()
            & $runner @entry | Out-Null
            Assert-Suite ($global:Api21FixtureCalls.Contains('exit-verifier') -and !$global:Api21FixtureCalls.Contains('full-collector') -and
                !(Test-Path "$root/final-results.json")) 'Selected ordinary mode bypassed shared exit gate or claimed full qualification'
            foreach ($fault in @('normal-case-debuggerd','normal-final-debuggerd','normal-capture-owner','normal-capture-failure','normal-late-stdout')) {
                $global:Api21FixtureMutation=$fault;$global:Api21FixtureStopped=$false
                $entry.RunName=$fault
                $global:Api21FixtureCalls.Clear()
                Expect-SuiteFailure { & $runner @entry | Out-Null } 'Fatal cleanup error|API21 post-cleanup termination evidence is incomplete|Required final Android log capture failed|Artifact bytes differ'
                Assert-Suite ($global:Api21FixtureStopped -and !(Test-Path "$root/final-results.json")) "Failed ordinary $fault retained current PASS or leaked owned tree"
                if ($fault -eq 'normal-case-debuggerd') {
                    Assert-Suite (@($global:Api21FixtureCalls | Where-Object { $_ -like 'shell am start *' }).Count -eq 1 -and
                        @(Get-Content "$root/$fault/network-gui/logcat-after-cleanup.log" | Where-Object { $_ -like '*DEBUG*' }).Count) 'Case debuggerd was not captured before the next clear'
                }
            }
            $global:Api21FixtureMutation='normal-case-debuggerd'
            $entry.Remove('CaseNames');$entry.RunName='full-case-debuggerd'
            $global:Api21FixtureCalls.Clear()
            Expect-SuiteFailure { & $runner @entry | Out-Null } 'Fatal cleanup error'
            Assert-Suite (@($global:Api21FixtureCalls | Where-Object { $_ -like 'shell am start *' }).Count -eq 1 -and
                !(Test-Path "$root/final-results.json")) 'Full runner cleared a failed first case and continued'
        }
    }
    $global:Api21FixtureMutation=''
    Write-Output 'PASS: ordinary full/selected Qt5/Qt6, sound and API10-forward API21 recordings across four ABIs require per-case cleanup/stdout and owned final capture; no ADB/emulator executes'


} finally {
    foreach ($name in @('Get-Process','Start-Sleep','python')) { Remove-Item "Function:$name" -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $fixture) {
        $resolved=(Resolve-Path -LiteralPath $fixture).Path
        if ([IO.Path]::GetDirectoryName($resolved) -ne $parent -or [IO.Path]::GetFileName($resolved) -notlike 'android-api21-suite-*') { throw 'Unexpected API21 fixture cleanup path' }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
    Remove-Variable AndroidOwnedFixture,AndroidOwnedMockControls -Scope Global -ErrorAction SilentlyContinue
    Get-Variable -Name 'Api21Fixture*' -Scope Global | Remove-Variable -Scope Global
}
