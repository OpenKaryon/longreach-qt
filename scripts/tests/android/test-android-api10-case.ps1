# SPDX-License-Identifier: GPL-3.0-or-later
<# Real API10 runner, actual metadata/leases/files; ADB/emulator boundaries recorded. #>
param([string]$RepoRoot=(Resolve-Path "$PSScriptRoot/../../..").Path)
$ErrorActionPreference='Stop'
$global:Api10SerialEmulatorStops=0
$parent=(New-Item -ItemType Directory -Force "$RepoRoot/build/fixtures").FullName
$fixture=Join-Path $parent ('android-api10-case-'+[guid]::NewGuid())
$global:Api10FixtureRepo=$RepoRoot
$global:Api10FixtureHome=$fixture
$global:Api10FixturePython=(Get-Command python).Source
$global:Api10FixtureCalls=[Collections.Generic.List[string]]::new()
$global:Api10FixtureMutation=''
$global:Api10FixtureMarker=''
$global:Api10FixturePackage='org.longreachqt.examples.qtselftest'
$global:Api10FixtureProcess=$null
$global:Api10FixtureRun=0
$global:Api10SoundReport=$null
$global:AndroidOwnedFixture=@{Repo=$RepoRoot;Python=$global:Api10FixturePython;RecordStart=$true}
$rootLock=$null
$caseLock=$null
function Assert-Runner([bool]$Condition,[string]$Message) { if (!$Condition) { throw $Message } }
function Expect-RunnerFailure([scriptblock]$Action,[string]$Message) {
    try { & $Action } catch { Assert-Runner ($_.Exception.Message -match $Message) "Unexpected runner failure: $_"; return }
    throw 'Expected API10 runner refusal'
}
function Get-Process { param($Name,$ErrorAction) return $null }
function Start-Sleep { param($Seconds,$Milliseconds) }
function Start-Process {
    param($FilePath,$ArgumentList,$WindowStyle,[switch]$PassThru,$RedirectStandardOutput,$RedirectStandardError)
    Assert-Runner ($WindowStyle -eq 'Hidden') 'Runner requested a visible emulator window'
    $global:Api10FixtureCalls.Add('start-emulator')
    $global:Api10FixtureRun++
    [IO.File]::WriteAllText($RedirectStandardOutput,"recorded emulator stdout $global:Api10FixtureRun")
    [IO.File]::WriteAllText($RedirectStandardError,"recorded emulator stderr $global:Api10FixtureRun")
    $global:Api10FixtureProcess=[pscustomobject]@{Id=9100+$global:Api10FixtureRun;HasExited=$false}
    $global:Api10FixtureProcess | Add-Member ScriptMethod Refresh { }
    $global:Api10FixtureProcess | Add-Member ScriptMethod WaitForExit { param($Milliseconds); $this.HasExited=$true; return $true }
    return $global:Api10FixtureProcess
}
function Stop-Process { param($InputObject); $InputObject.HasExited=$true }
function Invoke-ContendingRunner([string]$CaseDirectory) {
    $info=[Diagnostics.ProcessStartInfo]::new((Get-Command pwsh).Source)
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    foreach ($argument in @('-NoProfile','-File',"$RepoRoot/scripts/run/qt5-android-gingerbread.ps1",'-Abi','x86',
        '-Apk',$entry.Apk,'-AndroidSdk',$entry.AndroidSdk,'-SystemDirectory',$entry.SystemDirectory,
        '-Emulator',$entry.Emulator,'-Kernel',$entry.Kernel,'-Ramdisk',$entry.Ramdisk,
        '-OutputDirectory',$CaseDirectory,'-ArtifactRoot',$assets)) { $info.ArgumentList.Add($argument) }
    $child=[Diagnostics.Process]::Start($info)
    try {
        if (!$child.WaitForExit(10000)) { throw 'Owned contender did not finish' }
        $log=$child.StandardOutput.ReadToEnd()+$child.StandardError.ReadToEnd()
        Assert-Runner ($child.ExitCode -ne 0 -and $log -like '*Another Longreach operation owns*') "Contender did not refuse the real lease: $log"
    } finally {
        if (!$child.HasExited) { $child.Kill(); $child.WaitForExit(5000) | Out-Null }
        $child.Dispose()
    }
}
try {
    foreach ($relative in @('scripts/run/android/android-adb-endpoint.ps1','scripts/run/android/android-shell.ps1','scripts/run/android/android-emulator-state.ps1','scripts/run/qt5-android-gingerbread.ps1','scripts/run/android/android-cpu.ps1',
            'scripts/run/android/android-cpu.py','scripts/build/android-api21/artifact-lock.ps1','tests/expected-apps.txt')) {
        $destination=Join-Path $fixture $relative
        New-Item -ItemType Directory -Force (Split-Path $destination) | Out-Null
        Copy-Item -LiteralPath (Join-Path $RepoRoot $relative) -Destination $destination
    }
    @'
import importlib.util, pathlib, sys
repo, root = map(pathlib.Path, sys.argv[1:])
sys.path.insert(0, str(repo / 'scripts/tests/android'))
import android_result_fixtures as fixtures
spec = importlib.util.spec_from_file_location('api10_fixture_artifacts', repo / 'scripts/build/android-api21/artifact-manifest.py')
artifacts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(artifacts)
root.mkdir(parents=True, exist_ok=True)
fixtures.packaged(root, 5, artifacts, abi='x86')
'@ | Set-Content "$fixture/seed.py"
    $assets=(New-Item -ItemType Directory -Force "$fixture/assets").FullName
    & $global:Api10FixturePython "$fixture/seed.py" $RepoRoot $assets
    if ($LASTEXITCODE) { throw 'Could not seed synthetic APK metadata' }
    New-Item -ItemType Directory -Force "$fixture/sdk/platform-tools","$fixture/media","$fixture/tools","$assets/harness" | Out-Null
    foreach ($path in @('sdk/platform-tools/adb.exe','media/kernel','media/ramdisk','media/userdata.img','tools/custom-emulator.exe')) {
        [IO.File]::WriteAllText((Join-Path $fixture $path),'recording fixture input')
    }
    '. "$($global:AndroidOwnedFixture.Repo)/scripts/tests/android/android-owned-process-mock.ps1"' | Set-Content "$fixture/scripts/run/android/android-owned-process.ps1"
    @'
. "$global:Api10FixtureRepo/scripts/run/android/android-case-state.ps1"
function Invoke-AndroidTool([string]$Program,[string[]]$Arguments) {
    $global:LASTEXITCODE=0
    if ($Program -eq 'python') {
        $relative=[IO.Path]::GetRelativePath($global:Api10FixtureHome,$Arguments[0])
        $actual=Join-Path $global:Api10FixtureRepo $relative
        if ([IO.Path]::GetFileName($actual) -eq 'require-android-sound-cache.py') { $global:Api10FixtureCalls.Add('sound-output-validator') }
        & $global:Api10FixturePython $actual @($Arguments | Select-Object -Skip 1)
        if ($LASTEXITCODE) { throw 'Actual metadata validator failed' }
        return
    }
    if ([IO.Path]::GetFileName($Program) -ne 'adb.exe') { throw 'Unexpected external fixture tool' }
    if ($Arguments -contains 'getprop') {
        switch ($Arguments[-1]) { 'ro.build.version.sdk' {'10'} 'ro.build.version.release' {'2.3.7'} 'ro.product.cpu.abi' {'x86'} }
        return
    }
    if ($Arguments -contains '/proc/cpuinfo') { return @('processor: 0','flags: ssse3') }
    if ($Arguments -contains 'push') {
        $global:Api10FixtureCalls.Add('push')
        if ($global:Api10FixtureMutation -eq 'push-timeout') { throw 'ADB command timed out: recorded push' }
        if ($global:Api10FixtureMutation -eq 'apk-during-push') { [IO.File]::AppendAllText($Arguments[3],'replaced during transfer') }
        return
    }
    if ($Arguments -contains 'install') {
        $global:Api10FixtureCalls.Add('install')
        if ($global:Api10FixtureMutation -eq 'manifest-after-install') { [IO.File]::AppendAllText("$global:Api10FixtureHome/assets/apk-manifest.json","`n") }
        return 'Success'
    }
    if ($Arguments -contains 'log') { $global:Api10FixtureMarker=$Arguments[-1]; return }
    if ($Arguments -contains 'am' -and $Arguments -contains 'start') {
        $global:Api10FixtureCalls.Add('launch')
        if ($null -ne $global:Api10SoundReport) {
            $index=[Array]::IndexOf($Arguments,'applicationArguments')
            Assert-Runner ($index -ge 0 -and $Arguments[$index+1] -ceq '--sound-cache-teardown') 'Sound diagnostic argv changed'
        }
        $component=$Arguments[[Array]::IndexOf($Arguments,'-n')+1]
        $global:Api10FixturePackage=$component.Split('/')[0]
        return "Starting: Intent { cmp=$component (has extras) }"
    }
    if ($Arguments -contains 'pull') {
        $destination=Join-Path $Arguments[-1] 'files'
        New-Item -ItemType Directory -Force $destination | Out-Null
        $names=@(Get-Content "$global:Api10FixtureRepo/tests/common/moderncpp-required.txt" | Where-Object { $_ -and !$_.StartsWith('#') })
        $lines=@('__cplusplus: 202302')+@($names | ForEach-Object { 'PASS: '+$_ })+@('---- qt-selftest: 25 passed, 0 failed, 0 skipped ----')
        if ($null -ne $global:Api10SoundReport) { $lines=$global:Api10SoundReport }
        $lines | Set-Content "$destination/selftest.stdout"
        $lines | Set-Content "$destination/strict-cxx23.log"
        [IO.File]::WriteAllText("$destination/selftest-result.txt",'0')
        [IO.File]::WriteAllText("$destination/probe-result.txt",'0')
        return
    }
    if ($Arguments -contains 'start-server' -or $Arguments -contains 'input' -or $Arguments -contains 'logcat') { return }
    throw ('Unexpected recorded ADB command: '+($Arguments -join ' '))
}
'@ | Set-Content "$fixture/scripts/run/android/android-case-state.ps1"
    @'
function Wait-AndroidBoot {
    param($Adb,$Serial,$RunDirectory,$EmulatorPid,$TimeoutSeconds,$EmulatorProcess)
    if ($global:Api10FixtureMutation -eq 'apk-at-boot') { [IO.File]::AppendAllText("$global:Api10FixtureHome/assets/apk/qt-selftest.apk",'changed at boot') }
}
function Set-AndroidGuestStayAwake { param($Adb,$Serial,$RunDirectory); [IO.File]::WriteAllText("$RunDirectory/power-before.txt",'mStayOnConditions=3') }
'@ | Set-Content "$fixture/scripts/run/android/android-wait-boot.ps1"
    @'
. "$global:Api10FixtureRepo/scripts/run/android/android-process-exit.ps1"
# Guest capture transport has its own recording fixture. Keep this runner
# fixture's application/lifecycle mutations at the same ADB log boundary.
function Start-AndroidCaseLogCapture {
    param($Adb,$Serial,$Directory)
    '{}' | Set-Content "$Directory/logcat-capture.json"
    return (Get-FileHash "$Directory/logcat-capture.json").Hash.ToLowerInvariant()
}
function Get-AndroidCaseRawLog {
    param($Adb,$Serial,$Directory,$Name,$TimeoutMilliseconds)
    $lines=@(Invoke-AndroidExitQuery $Adb $Serial @('logcat','-d','-v','brief') $Directory $Name $TimeoutMilliseconds)
    $lines | Set-Content "$Directory/$Name.stdout"
    '{}' | Set-Content "$Directory/$Name-file-capture.json"
    return $lines
}
function Invoke-AndroidExitQuery {
    param($Adb,$Serial,[string[]]$Command,$Directory,$Name,$TimeoutMilliseconds,[switch]$AllowNonzero)
    if ($Command[0] -eq 'emu') { $global:Api10SerialEmulatorStops++;throw 'Fixture: serial-based emulator termination must not run' }
    if ($Command[0] -eq 'shell' -and $Command[1] -eq 'cat') { return '0' }
    if ($Command[0] -eq 'shell' -and $Command[1] -eq 'ps') { return @('USER PID PPID VSIZE RSS WCHAN PC NAME','root 1 0 0 0 0 0 /init') }
    if ($Command[0] -eq 'logcat') {
        if ($Name -eq 'final-logcat') {
            if ($global:Api10FixtureMutation -eq 'final-log-failure') { throw 'Controlled final log query failure' }
            if ($global:Api10FixtureMutation -eq 'sound-stdout-cleanup') { [IO.File]::AppendAllText("$Directory/files/selftest.stdout", "`nSOUND_CACHE: return=0`n") }
        if ($global:Api10FixtureMutation -eq 'late-manifest') { [IO.File]::AppendAllText("$global:Api10FixtureHome/assets/apk-manifest.json","`n") }
        if ($global:Api10FixtureMutation -eq 'late-host-owner') {
            $path=Join-Path $Directory 'host-process-owner.json'
            $owner=Get-Content $path -Raw | ConvertFrom-Json
            $owner.supervisor_creation_filetime='124'
            $owner | ConvertTo-Json | Set-Content $path
        }
        }
        $lines=@("I/LongreachCase( 123): $global:Api10FixtureMarker",
            "I/ActivityManager( 60): Start proc $global:Api10FixturePackage for activity $global:Api10FixturePackage/.Activity: pid=1234 uid=10001 gids={}")
        if ($global:Api10FixtureMutation -eq 'sound-fatal') { $lines+='E/AndroidRuntime(1234): FATAL EXCEPTION: main' }
        if ($global:Api10FixtureMutation -eq 'sound-late-debuggerd' -and $Name -eq 'final-logcat') {
            $lines+='I/DEBUG( 99): *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***'
            $lines+="I/DEBUG( 99): pid: 1234, tid: 1234  >>> $global:Api10FixturePackage <<<"
            $lines+='I/DEBUG( 99): signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr 00000000'
        }
        $lines+="I/ActivityManager( 60): Process $global:Api10FixturePackage (pid 1234) has died."
        return $lines
    }
    throw ('Unexpected recorded exit query: '+($Command -join ' '))
}
'@ | Set-Content "$fixture/scripts/run/android/android-process-exit.ps1"
    foreach ($script in @(Get-ChildItem -LiteralPath "$fixture/scripts/run" -Filter '*.ps1' -Recurse)) {
        $tokens=$null;$errors=$null
        $null=[Management.Automation.Language.Parser]::ParseFile($script.FullName,[ref]$tokens,[ref]$errors)
        if ($errors.Count) { throw "Generated fixture script $($script.Name): $($errors.Message -join '; ')" }
    }
    $case=Join-Path $assets 'harness/strict-cxx23'
    $entry=@{Abi='x86';Apk="$assets/apk/qt-selftest.apk";SystemDirectory="$fixture/media";
        Emulator="$fixture/tools/custom-emulator.exe";Kernel="$fixture/media/kernel";Ramdisk="$fixture/media/ramdisk";
        OutputDirectory=$case;AndroidSdk="$fixture/sdk";Package='org.longreachqt.examples.qtselftest';StrictCxx23=$true;
        SdkImageId=('sha256:'+('a'*64));CaseName='strict-cxx23';BatchReceipt="$assets/harness/batch-receipt.json";ArtifactRoot=$assets}
    @{schema_version=1;batch_id=('b'*32);run='harness';abi='x86';api=10;sdk_image_id=$entry.SdkImageId;
      apk_manifest_sha256=(Get-FileHash "$assets/apk-manifest.json").Hash.ToLowerInvariant();
      emulator_sha256=(Get-FileHash $entry.Emulator).Hash.ToLowerInvariant()} | ConvertTo-Json | Set-Content $entry.BatchReceipt
    . "$RepoRoot/scripts/build/android-api21/artifact-lock.ps1"
    [IO.File]::WriteAllText("$assets/final-results.json",'current owner report')
    $rootLock=Enter-AndroidArtifactLock $assets
    Invoke-ContendingRunner (Join-Path $assets 'blocked-root')
    Assert-Runner (!(Test-Path "$assets/blocked-root")) 'Busy root created case state'
    Assert-Runner ([IO.File]::ReadAllText("$assets/final-results.json") -ceq 'current owner report') 'Root contender invalidated owner report'
    $rootLock.Dispose();$rootLock=$null
    $caseLock=Enter-AndroidArtifactLock $case
    Invoke-ContendingRunner $case
    Assert-Runner ([IO.File]::ReadAllText("$assets/final-results.json") -ceq 'current owner report') 'Busy case invalidated owner report'
    $caseLock.Dispose();$caseLock=$null
    $runner="$fixture/scripts/run/qt5-android-gingerbread.ps1"
    & $runner @entry | Out-Null
    $first=Get-Content "$case/input-receipt.json" -Raw | ConvertFrom-Json
    Assert-Runner ($first.completed -and $first.emulator_exit_confirmed -and $first.apk_manifest_bound) 'Real runner did not complete its bound case'
    Assert-Runner (!$first.qualification -and $first.scope -eq 'single-case') 'Single case claimed full qualification'
    Assert-Runner ($first.case_attempt_id -cmatch '^[0-9a-f]{32}$') 'Case attempt ID missing'
    Assert-Runner (!(Test-Path "$assets/final-results.json")) 'Real standalone entry retained old aggregate PASS'
    Assert-Runner (@(Get-ChildItem $case -Filter 'attempt-*.pending.json').Count -eq 0) 'Successful case kept a pending attempt'
    $saved=[IO.File]::ReadAllText("$case/input-receipt.json")
    $stdout=[IO.File]::ReadAllText("$case/emulator.stdout")
    & $runner @entry | Out-Null
    $second=Get-Content "$case/input-receipt.json" -Raw | ConvertFrom-Json
    $history=Join-Path $case ('previous-'+$second.case_attempt_id)
    Assert-Runner ($first.case_attempt_id -cne $second.case_attempt_id) 'Rerun reused an attempt ID'
    Assert-Runner ([IO.File]::ReadAllText("$history/input-receipt.json") -ceq $saved -and [IO.File]::ReadAllText("$history/emulator.stdout") -ceq $stdout) 'Rerun lost prior metadata/emulator logs'
    foreach ($name in @('files/selftest.stdout','process-exit.json','guest-cpu-baseline.json','final-logcat.log','userdata-qemu.img','emulator.pid')) {
        Assert-Runner (Test-Path -LiteralPath (Join-Path $history $name)) "Full attempt history lost $name"
    }
    $apkBytes=[IO.File]::ReadAllBytes($entry.Apk)
    $manifestBytes=[IO.File]::ReadAllBytes("$assets/apk-manifest.json")
    $priorReceipt=[IO.File]::ReadAllText("$case/input-receipt.json")
    [IO.File]::AppendAllText($entry.Apk,'changed before preflight')
    Expect-RunnerFailure { & $runner @entry | Out-Null } 'Artifact bytes differ|Owned process tree changed|ADB command timed out'
    Assert-Runner ([IO.File]::ReadAllText("$case/input-receipt.json") -ceq $priorReceipt) 'Preflight failure overwrote prior evidence'
    $pending=@(Get-ChildItem $case -Filter 'attempt-*.pending.json')
    Assert-Runner ($pending.Count -eq 1 -and (Get-Content $pending[0].FullName -Raw | ConvertFrom-Json).failed) 'Preflight failure did not mark its own incomplete attempt'
    [IO.File]::WriteAllBytes($entry.Apk,$apkBytes)
    & $runner @entry | Out-Null
    Assert-Runner (@(Get-ChildItem $case -Filter 'attempt-*.pending.json').Count -eq 0) 'Explicit recovery did not archive the failed preflight'
    foreach ($mutation in @('apk-at-boot','apk-during-push','manifest-after-install','late-manifest','late-host-owner','push-timeout')) {
        $global:Api10FixtureMutation=$mutation
        $global:Api10FixtureCalls.Clear()
        Expect-RunnerFailure { & $runner @entry | Out-Null } 'Artifact bytes differ|Owned process tree changed|ADB command timed out'
        $failed=Get-Content "$case/input-receipt.json" -Raw | ConvertFrom-Json
        Assert-Runner (!$failed.completed -and @(Get-ChildItem $case -Filter 'attempt-*.pending.json').Count -eq 1) "Failed $mutation case advertised completion"
        Assert-Runner ($global:Api10FixtureProcess.HasExited) "Failed $mutation leaked the owned fake emulator"
        if ($mutation -notin @('late-manifest','late-host-owner')) { Assert-Runner (!$global:Api10FixtureCalls.Contains('launch')) "Changed $mutation reached app launch" }
        [IO.File]::WriteAllBytes($entry.Apk,$apkBytes)
        [IO.File]::WriteAllBytes("$assets/apk-manifest.json",$manifestBytes)
    }
    $global:Api10FixtureMutation='final-log-failure'
    Expect-RunnerFailure { & $runner @entry | Out-Null } 'Controlled final log query failure'
    Assert-Runner ($global:Api10FixtureProcess.HasExited) 'A diagnostic write failure bypassed owned tree shutdown'
    Assert-Runner (!(Get-Content "$case/input-receipt.json" -Raw | ConvertFrom-Json).completed) 'Cleanup failure advertised completed case'
    $global:Api10FixtureMutation=''
    $probe=@{}+$entry
    foreach ($name in @('CaseName','BatchReceipt','Package')) { $probe.Remove($name) }
    $probe.RuntimeProbe=$true
    $probe.OutputDirectory=Join-Path $assets 'focused-runtime'
    & $runner @probe | Out-Null
    $diagnostic=Get-Content "$($probe.OutputDirectory)/input-receipt.json" -Raw | ConvertFrom-Json
    Assert-Runner ($diagnostic.completed -and !$diagnostic.apk_manifest_bound -and !$diagnostic.qualification -and $diagnostic.termination_policy -eq 'jni-return') 'RuntimeProbe compatibility/classification changed'
    # Independent synthetic pre-exit data, passed through the actual new CLI.
    $soundPhases=@('SOUND_CACHE: protocol=1','SOUND_CACHE: wav=pcm-s16le-8000-mono',
        'SOUND_CACHE: ready=1','SOUND_CACHE: playing=1','SOUND_CACHE: destroyed=1','SOUND_CACHE: return=0')
    $sound=@{}+$entry
    foreach ($name in @('StrictCxx23','CaseName','BatchReceipt')) { $sound.Remove($name) }
    $sound.Apk="$assets/apk/extended/qt-selftest.apk"
    $sound.ApplicationArguments='--sound-cache-teardown'
    $sound.OutputDirectory=Join-Path $assets 'sound-cache-diagnostic'
    foreach ($index in 1..2) {
        $global:Api10SoundReport=$soundPhases
        & $runner @sound | Out-Null
        $diagnostic=Get-Content "$($sound.OutputDirectory)/input-receipt.json" -Raw | ConvertFrom-Json
        Assert-Runner ($diagnostic.completed -and !$diagnostic.qualification -and $diagnostic.diagnostic -ceq 'qt5-sound-cache-teardown') 'Sound output was promoted to qualification'
        Assert-Runner ($diagnostic.apk_manifest_bound -and $diagnostic.apk_relative -ceq 'apk/extended/qt-selftest.apk') 'Sound diagnostic accepted an unbound APK'
        Assert-Runner ($diagnostic.process_exit_confirmed -and $diagnostic.termination_policy -ceq 'natural' -and $diagnostic.process_id -eq 1234) 'Sound output bypassed the process-exit gate'
        Assert-Runner ($diagnostic.diagnostic_stdout_sha256 -ceq $diagnostic.stdout_sha256 -and $diagnostic.stdout_sha256 -ceq (Get-FileHash "$($sound.OutputDirectory)/files/selftest.stdout").Hash.ToLowerInvariant()) 'Sound completion was not bound to the validated stdout bytes'
        Assert-Runner ($global:Api10FixtureProcess.HasExited) 'Sound diagnostic leaked its fake owned emulator'
        if ($index -eq 1) { $firstSound=$diagnostic.case_attempt_id }
    }
    Assert-Runner ($firstSound -cne $diagnostic.case_attempt_id -and
        (Test-Path "$($sound.OutputDirectory)/previous-$($diagnostic.case_attempt_id)/input-receipt.json")) 'Sound rerun lost its separate attempt/history'
    foreach ($fault in @('missing-destroy','duplicate-return','wrong-ready','wrong-order','explicit-failure','old-selftest')) {
        $global:Api10SoundReport=switch ($fault) {
            'missing-destroy' { $soundPhases | Where-Object { $_ -cne 'SOUND_CACHE: destroyed=1' } }
            'duplicate-return' { $soundPhases; 'SOUND_CACHE: return=0' }
            'wrong-ready' { $soundPhases -creplace 'ready=1','ready=0' }
            'wrong-order' { $soundPhases[5..0] }
            'explicit-failure' { $soundPhases; 'FAIL: local sample did not become Ready' }
            'old-selftest' { '---- qt-selftest: 106 passed, 0 failed, 4 skipped ----' }
        }
        Expect-RunnerFailure { & $runner @sound | Out-Null } 'Actual metadata validator failed'
        $failed=Get-Content "$($sound.OutputDirectory)/input-receipt.json" -Raw | ConvertFrom-Json
        Assert-Runner (!$failed.completed -and !$failed.qualification -and
            @(Get-ChildItem $sound.OutputDirectory -Filter 'attempt-*.pending.json').Count -eq 1) "Invalid sound $fault output advertised completion"
        Assert-Runner ($global:Api10FixtureProcess.HasExited) "Invalid sound $fault output leaked the fake owned emulator"
    }
    $global:Api10SoundReport=$soundPhases
    $global:Api10FixtureMutation='sound-fatal'
    $global:Api10FixtureCalls.Clear()
    Expect-RunnerFailure { & $runner @sound | Out-Null } 'Fatal cleanup error'
    Assert-Runner (!$global:Api10FixtureCalls.Contains('sound-output-validator')) 'Sound protocol ran before fatal process evidence was checked'
    Assert-Runner (!(Get-Content "$($sound.OutputDirectory)/input-receipt.json" -Raw | ConvertFrom-Json).completed) 'Valid sound phases hid a process crash'
    Assert-Runner ($global:Api10FixtureProcess.HasExited) 'Fatal sound case leaked the fake owned emulator'
    $global:Api10FixtureMutation='sound-late-debuggerd'
    $global:Api10FixtureCalls.Clear()
    Expect-RunnerFailure { & $runner @sound | Out-Null } 'Fatal cleanup error'
    Assert-Runner ($global:Api10FixtureCalls.Contains('sound-output-validator')) 'Late debuggerd case did not first validate the sound phases'
    Assert-Runner (!(Get-Content "$($sound.OutputDirectory)/input-receipt.json" -Raw | ConvertFrom-Json).completed) 'Valid sound phases hid late own-process debuggerd'
    Assert-Runner ($global:Api10FixtureProcess.HasExited) 'Late sound debuggerd bypassed owned cleanup'
    $global:Api10FixtureMutation='sound-stdout-cleanup'
    Expect-RunnerFailure { & $runner @sound | Out-Null } 'Sound-cache stdout changed after validation'
    Assert-Runner (!(Get-Content "$($sound.OutputDirectory)/input-receipt.json" -Raw | ConvertFrom-Json).completed) 'Cleanup replaced the validated sound output'
    Assert-Runner ($global:Api10FixtureProcess.HasExited) 'Changed sound stdout leaked the fake owned emulator'
    $global:Api10FixtureMutation=''
    $starts=$global:Api10FixtureRun
    $prior=[IO.File]::ReadAllText("$($sound.OutputDirectory)/input-receipt.json")
    foreach ($field in @('StrictCxx23','RuntimeProbe','CaseName','BatchReceipt')) {
        $mixed=@{}+$sound
        $mixed[$field]=if ($field -in @('StrictCxx23','RuntimeProbe')) { $true } else { $entry[$field] }
        Expect-RunnerFailure { & $runner @mixed | Out-Null } 'standalone diagnostic'
    }
    foreach ($argument in @('--sound-cache-teardown --modern-cpp','--sound-cache-teardown --selftest','--sound-cache-teardown --sound-cache-teardown')) {
        $mixed=@{}+$sound; $mixed.ApplicationArguments=$argument
        Expect-RunnerFailure { & $runner @mixed | Out-Null } 'exactly --sound-cache-teardown'
    }
    Assert-Runner ($global:Api10FixtureRun -eq $starts -and
        [IO.File]::ReadAllText("$($sound.OutputDirectory)/input-receipt.json") -ceq $prior) 'Invalid sound preflight started a guest or replaced prior evidence'
    $manifestPath=Join-Path $assets 'apk-manifest.json'
    $unbound=@{}+$sound
    $unbound.OutputDirectory=Join-Path $assets 'unbound-sound'
    $manifestSaved=[IO.File]::ReadAllBytes($manifestPath)
    try {
        [IO.File]::Delete($manifestPath)
        Expect-RunnerFailure { & $runner @unbound | Out-Null } 'requires its APK manifest'
        Assert-Runner ($global:Api10FixtureRun -eq $starts) 'Unbound sound APK reached the fake emulator'
        Assert-Runner (!(Test-Path "$($unbound.OutputDirectory)/input-receipt.json")) 'Unbound sound APK advertised a receipt'
    } finally { [IO.File]::WriteAllBytes($manifestPath,$manifestSaved) }
    $global:Api10SoundReport=$null
    Assert-Runner ($global:Api10SerialEmulatorStops -eq 0) 'Serial-based emulator termination was attempted'
    Write-Output 'PASS: real API10 root/case contention, complete history, bound install/late-cleanup mutations, natural exit metadata, probe routing and sound pre-exit/exit separation'
} finally {
    if ($caseLock) { $caseLock.Dispose() }
    if ($rootLock) { $rootLock.Dispose() }
    foreach ($name in @('Get-Process','Start-Sleep','Start-Process','Stop-Process')) { Remove-Item "Function:$name" -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $fixture) {
        $resolved=(Resolve-Path -LiteralPath $fixture).Path
        if ([IO.Path]::GetDirectoryName($resolved) -ne $parent -or [IO.Path]::GetFileName($resolved) -notlike 'android-api10-case-*') { throw 'Unexpected API10 fixture cleanup path' }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
    Remove-Variable AndroidOwnedFixture,AndroidOwnedMockControls -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable Api10FixtureRepo,Api10FixtureHome,Api10FixturePython,Api10FixtureCalls,Api10FixtureMutation,Api10FixtureMarker,Api10FixturePackage,Api10FixtureProcess,Api10FixtureRun -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable Api10SerialEmulatorStops,Api10SoundReport -Scope Global -ErrorAction SilentlyContinue
}
