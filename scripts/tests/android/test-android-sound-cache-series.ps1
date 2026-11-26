# SPDX-License-Identifier: GPL-3.0-or-later
<# Actual series driver/collector, synthetic raw-case boundary; no ADB/guests/builds. #>
param([string]$RepoRoot=(Resolve-Path "$PSScriptRoot/../../..").Path)
$ErrorActionPreference='Stop'
$parent=(New-Item -ItemType Directory -Force "$RepoRoot/build/fixtures").FullName
$fixture=Join-Path $parent ('sound-cache-series-'+[guid]::NewGuid())
$global:SoundSeriesRepo=$RepoRoot
$global:SoundSeriesHome=$fixture
$global:SoundSeriesPython=(Get-Command python).Source
$global:SoundSeriesCalls=[Collections.Generic.List[object]]::new()
$global:SoundSeriesGuests=0
$global:SoundSeriesMutation=''
$global:SoundSeriesContend=$false
$global:SoundSeriesSawResult=$false
$savedLocation=(Get-Location).ProviderPath
$savedEnvironment=@{}
foreach ($name in @('ADB_SERVER_SOCKET','ANDROID_ADB_SERVER_ADDRESS','ANDROID_ADB_SERVER_PORT')) {
    $savedEnvironment[$name]=[Environment]::GetEnvironmentVariable($name)
}
function Reset-SeriesEndpoint {
    $env:ADB_SERVER_SOCKET='tcp:localhost:5037'
    $env:ANDROID_ADB_SERVER_ADDRESS='localhost'
    $env:ANDROID_ADB_SERVER_PORT='5037'
}
function Assert-Series([bool]$Condition,[string]$Message) { if (!$Condition) { throw $Message } }
function Expect-SeriesFailure([scriptblock]$Action,[string]$Message) {
    try { & $Action } catch { Assert-Series ($_.Exception.Message -match $Message) "Unexpected series failure: $_"; return }
    throw 'Expected sound series refusal'
}
function python {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    Assert-Series ([IO.Path]::GetFileName($Arguments[0]) -eq 'android-sound-cache-series.py') 'Unexpected external metadata tool'
    $action=$Arguments[1]
    $directory=$Arguments[[Array]::IndexOf($Arguments,'--directory')+1]
    $global:SoundSeriesCalls.Add(@{kind='metadata';action=$action})
    if ($action -eq 'checkpoint' -and $global:SoundSeriesMutation -eq 'media-before-2' -and
        $Arguments[[Array]::IndexOf($Arguments,'--index')+1] -eq '2') {
        $config=Get-Content "$directory/series-inputs.json" -Raw | ConvertFrom-Json
        [IO.File]::AppendAllText($config.paths.system,'changed before second attempt')
    }
    if ($action -eq 'verify' -and $global:SoundSeriesMutation -eq 'late-verify') {
        $global:SoundSeriesSawResult=Test-Path "$directory/series-result.json"
        & $global:SoundSeriesPython "$global:SoundSeriesHome/data.py" final-crash $global:SoundSeriesRepo $directory
        if ($LASTEXITCODE) { throw 'Could not create synthetic late final crash' }
    }
    & $global:SoundSeriesPython "$global:SoundSeriesRepo/scripts/run/android/android-sound-cache-series.py" @($Arguments | Select-Object -Skip 1)
    $validatorExit=$LASTEXITCODE
    $global:LASTEXITCODE=$validatorExit
}
function New-SeriesEntry([string]$Name) {
    Reset-SeriesEndpoint
    $root=Join-Path $fixture "$Name/artifacts with spaces"
    & $global:SoundSeriesPython "$fixture/data.py" prepare $RepoRoot $root
    if ($LASTEXITCODE) { throw 'Could not create synthetic producer generation' }
    $options=Get-Content (Join-Path ([IO.Path]::GetDirectoryName($root)) 'fixture-options.json') -Raw | ConvertFrom-Json
    return @{ArtifactRoot=$root;Abi=$options.abi;SystemDirectory=$options.system_directory;Emulator=$options.emulator;
        Kernel=$options.kernel;Ramdisk=$options.ramdisk;AndroidSdk=$options.android_sdk;ClassicEmulator=$true;RunName='recording-series'}
}
function Invoke-SeriesContender($Entry) {
    $info=[Diagnostics.ProcessStartInfo]::new((Get-Command pwsh).Source)
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    foreach ($arg in @('-NoProfile','-File',"$fixture/scripts/run/qt5-android-sound-cache.ps1")) { $info.ArgumentList.Add($arg) }
    foreach ($key in @('ArtifactRoot','Abi','SystemDirectory','Emulator','Kernel','Ramdisk','AndroidSdk')) {
        $info.ArgumentList.Add('-'+$key);$info.ArgumentList.Add([string]$Entry[$key])
    }
    $info.ArgumentList.Add('-ClassicEmulator')
    $child=[Diagnostics.Process]::Start($info)
    try {
        if (!$child.WaitForExit(10000)) { throw 'Owned series contender did not finish' }
        $text=$child.StandardOutput.ReadToEnd()+$child.StandardError.ReadToEnd()
        Assert-Series ($child.ExitCode -ne 0 -and $text -like '*Another Longreach operation owns*') "Series did not hold the real root lease: $text"
    } finally {
        if (!$child.HasExited) { $child.Kill();$child.WaitForExit(3000) | Out-Null }
        $child.Dispose()
    }
}
try {
    foreach ($relative in @('scripts/run/qt5-android-sound-cache.ps1','scripts/run/android/android-adb-endpoint.ps1',
            'scripts/build/android-api21/artifact-lock.ps1')) {
        $target=Join-Path $fixture $relative
        New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
        Copy-Item -LiteralPath (Join-Path $RepoRoot $relative) -Destination $target
    }
    @'
import json, pathlib, sys
action, repo, location = sys.argv[1:4]
sys.path.insert(0, str(pathlib.Path(repo) / 'scripts/tests/android'))
import android_sound_cache_fixtures as data
where = pathlib.Path(location)
if action == 'prepare':
    options = data.prepare(where)
    (where.parent / 'fixture-options.json').write_text(json.dumps({k: str(v) if isinstance(v, pathlib.Path) else v for k,v in options.items()}))
elif action == 'case':
    index = int(sys.argv[4])
    path, record = data.case(where, index, working_directory=pathlib.Path.cwd())
    if sys.argv[5] == 'bad-report':
        (path / 'files/selftest.stdout').write_text('---- qt-selftest: 106 passed, 0 failed, 4 skipped ----')
        record['stdout_sha256'] = record['diagnostic_stdout_sha256'] = data.series.digest(path / 'files/selftest.stdout')
        (path / 'input-receipt.json').write_text(json.dumps(record))
elif action == 'final-crash':
    path = where / 'run-01'
    final = path / 'final-logcat.log'
    with final.open('a') as stream:
        stream.write('\nI/DEBUG(99): *** *** ***\nI/DEBUG(99): pid: 1234, tid: 1234 >>> org.longreachqt.examples.qtselftest <<<\n')
    receipt = json.loads((path / 'input-receipt.json').read_text())
    receipt['final_logcat_sha256'] = data.series.digest(final)
    (path / 'input-receipt.json').write_text(json.dumps(receipt))
else:
    raise ValueError(action)
'@ | Set-Content "$fixture/data.py"
    @'
param($Abi,$Apk,$SystemDirectory,$Emulator,$Kernel,$Ramdisk,$OutputDirectory,$AndroidSdk,$Package,
      $ApplicationArguments,$ArtifactRoot,$SdkImageId,$RasterImageDepth,$QtQuickBackend,[switch]$ClassicEmulator)
$global:SoundSeriesGuests++
$index=$global:SoundSeriesGuests
Assert-Series ([IO.Path]::GetFileName($OutputDirectory) -ceq ('run-{0:d2}' -f $index)) 'Series retried or skipped a case index'
Assert-Series ($ApplicationArguments -ceq '--sound-cache-teardown' -and $Package -ceq 'org.longreachqt.examples.qtselftest' -and
    $RasterImageDepth -eq '32' -and $QtQuickBackend -ceq 'software' -and $ClassicEmulator -and
    $Apk -ceq "$ArtifactRoot/apk/extended/qt-selftest.apk") 'Series changed the raw diagnostic invocation'
. "$global:SoundSeriesRepo/scripts/build/android-api21/artifact-lock.ps1"
$nested=Enter-AndroidArtifactLock $ArtifactRoot
Assert-Series ($null -eq $nested -and (Get-AndroidArtifactLockStream $ArtifactRoot).CanRead) 'Nested raw call lost its parent root lease'
if ($global:SoundSeriesContend -and $index -eq 1) { Invoke-SeriesContender $global:SoundSeriesCurrentEntry }
$global:SoundSeriesCalls.Add(@{kind='guest';index=$index;directory=$OutputDirectory})
if ($global:SoundSeriesMutation -eq 'throw-at-3' -and $index -eq 3) {
    New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
    [IO.File]::WriteAllText("$OutputDirectory/attempt-fixture.pending.json",'retained incomplete synthetic guest')
    throw 'Recorded guest failure at attempt three'
}
$mode=if ($global:SoundSeriesMutation -eq 'bad-report-at-2' -and $index -eq 2) { 'bad-report' } else { 'valid' }
& $global:SoundSeriesPython "$global:SoundSeriesHome/data.py" case $global:SoundSeriesRepo (Split-Path $OutputDirectory) $index $mode
if ($LASTEXITCODE) { throw 'Could not create synthetic raw case evidence' }
if ($global:SoundSeriesMutation -eq 'endpoint-after-1' -and $index -eq 1) {
    $env:ADB_SERVER_SOCKET='tcp:localhost:5048';$env:ANDROID_ADB_SERVER_PORT='5048'
}
'@ | Set-Content "$fixture/scripts/run/qt5-android-gingerbread.ps1"
    foreach ($script in @(Get-ChildItem "$fixture/scripts/run" -Filter '*.ps1' -Recurse)) {
        $tokens=$null;$parseErrors=$null
        [Management.Automation.Language.Parser]::ParseFile($script.FullName,[ref]$tokens,[ref]$parseErrors) | Out-Null
        if ($parseErrors.Count) { throw "Fixture $($script.Name): $($parseErrors.Message -join '; ')" }
    }
    $caller=New-Item -ItemType Directory -Path (Join-Path $fixture 'caller directory with spaces')
    Set-Location -LiteralPath $caller.FullName
    $driver="$fixture/scripts/run/qt5-android-sound-cache.ps1"
    $entry=New-SeriesEntry 'success'
    $global:SoundSeriesCurrentEntry=$entry
    $global:SoundSeriesContend=$true
    & $driver @entry | Out-Null
    $directory=Join-Path $entry.ArtifactRoot 'diagnostics/recording-series'
    $report=Get-Content "$directory/series-result.json" -Raw | ConvertFrom-Json
    $frozen=Get-Content "$directory/series-inputs.json" -Raw | ConvertFrom-Json
    Assert-Series ($frozen.working_directory -ceq $caller.FullName) 'Series did not freeze the real caller directory with spaces'
    Assert-Series ($global:SoundSeriesGuests -eq 20 -and $report.completed -and !$report.qualification -and $report.completed_processes -eq 20) 'Series did not validate exactly twenty separate diagnostics'
    Assert-Series (@($report.cases | Select-Object -ExpandProperty process_id -Unique).Count -eq 1 -and
        @($report.cases | Select-Object -ExpandProperty host_run_id -Unique).Count -eq 20) 'Repeated Android PID was confused with repeated host ownership'
    Assert-Series (!(Test-Path "$directory/series.pending.json")) 'Complete series retained pending state'
    $saved=[IO.File]::ReadAllBytes("$directory/series-result.json")
    Expect-SeriesFailure { & $driver @entry | Out-Null } 'metadata begin failed'
    Assert-Series ($global:SoundSeriesGuests -eq 20 -and [Convert]::ToBase64String([IO.File]::ReadAllBytes("$directory/series-result.json")) -ceq [Convert]::ToBase64String($saved)) 'Rerun replaced the previous series or retried it'
    $global:SoundSeriesContend=$false
    foreach ($mutation in @('throw-at-3','bad-report-at-2','media-before-2','endpoint-after-1','late-verify')) {
        $entry=New-SeriesEntry $mutation
        $global:SoundSeriesCurrentEntry=$entry
        $global:SoundSeriesGuests=0;$global:SoundSeriesCalls.Clear();$global:SoundSeriesMutation=$mutation
        $expected=if ($mutation -eq 'throw-at-3') { 'Recorded guest failure' } elseif ($mutation -eq 'endpoint-after-1') { 'ADB endpoint changed' } else { 'metadata (record|checkpoint|verify) failed' }
        Expect-SeriesFailure { & $driver @entry | Out-Null } $expected
        $directory=Join-Path $entry.ArtifactRoot 'diagnostics/recording-series'
        $failed=Get-Content "$directory/series-failure.json" -Raw | ConvertFrom-Json
        $count=switch ($mutation) { 'throw-at-3' {3} 'bad-report-at-2' {2} 'media-before-2' {1} 'endpoint-after-1' {1} 'late-verify' {20} }
        Assert-Series ($global:SoundSeriesGuests -eq $count -and !$failed.completed -and !$failed.qualification) "Failed $mutation series retried or advertised success"
        Assert-Series (!(Test-Path "$directory/series-result.json")) "Failed $mutation series retained a current final result"
        if ($mutation -eq 'throw-at-3') {
            Assert-Series (@(Get-ChildItem $directory -Filter 'accepted-*.json').Count -eq 2 -and
                (Test-Path "$directory/run-03/attempt-fixture.pending.json") -and !(Test-Path "$directory/run-04")) 'Guest failure lost accepted/failed attempts or continued'
        }
        if ($mutation -eq 'late-verify') {
            Assert-Series ($global:SoundSeriesSawResult -and (Test-Path "$directory/series-result-before-failure.json") -and
                @(Get-ChildItem $directory -Filter 'accepted-*.json').Count -eq 20) 'Late verify failure did not preserve its quarantined result and twenty attempts'
        }
    }
    $global:SoundSeriesMutation='';$global:SoundSeriesGuests=0
    $entry=New-SeriesEntry 'generation-failure'
    [IO.File]::AppendAllText((Join-Path $entry.ArtifactRoot 'native/libc++_shared.so'),'changed before begin')
    Expect-SeriesFailure { & $driver @entry | Out-Null } 'metadata begin failed'
    Assert-Series ($global:SoundSeriesGuests -eq 0 -and !(Test-Path (Join-Path $entry.ArtifactRoot 'diagnostics'))) 'Bad native generation started work or created a series'
    Write-Output 'PASS: fixed 20 actual-source driver/collector recordings, real root contention, no retries, media/endpoint/generation guards and late-result quarantine; no guests'
} finally {
    Set-Location -LiteralPath $savedLocation
    foreach ($name in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name,$savedEnvironment[$name]) }
    Remove-Item Function:python -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $fixture) {
        $resolved=(Resolve-Path -LiteralPath $fixture).Path
        if ([IO.Path]::GetDirectoryName($resolved) -ne $parent -or [IO.Path]::GetFileName($resolved) -notlike 'sound-cache-series-*') { throw 'Unexpected series fixture cleanup path' }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
    Remove-Variable SoundSeriesRepo,SoundSeriesHome,SoundSeriesPython,SoundSeriesCalls,SoundSeriesGuests,SoundSeriesMutation,SoundSeriesContend,SoundSeriesSawResult,SoundSeriesCurrentEntry -Scope Global -ErrorAction SilentlyContinue
}
