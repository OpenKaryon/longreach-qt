# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
# Exercise actual startup argv/receipts with recording Docker/process boundaries.
param([string]$RepoRoot=(Resolve-Path "$PSScriptRoot/../..").Path)
$ErrorActionPreference='Stop'
$parent=(New-Item -ItemType Directory -Force "$RepoRoot/build/fixtures").FullName
$fixture=Join-Path $parent ('api21-launch-'+[guid]::NewGuid())
$global:AndroidLaunchCalls=[Collections.Generic.List[object]]::new()
$global:AndroidLaunchPython=(@(Get-Command python -CommandType Application)[0]).Source
$global:AndroidLaunchMediaRepo=Join-Path $fixture 'synthetic-media-repo'
$global:AndroidLaunchRepo=$RepoRoot
$global:AndroidOwnedFixture=@{Repo=$RepoRoot;Python=$global:AndroidLaunchPython;RecordStart=$true}
$global:AndroidLaunchBusyProcess=''
function Get-Process {
    param($Name,$ErrorAction)
    if ($global:AndroidLaunchBusyProcess -and @($Name | Where-Object { $global:AndroidLaunchBusyProcess -like $_ }).Count) {
        return [pscustomobject]@{Name=$global:AndroidLaunchBusyProcess}
    }
    return $null
}
function docker { param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments) $global:LASTEXITCODE=0 }
function python {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    if ($Arguments[0] -notlike '*android-api21-identity.py' -or $Arguments[1] -ne 'capture') { throw 'Unexpected Python boundary' }
    $root=$Arguments[[Array]::IndexOf($Arguments,'--root')+1]
    $run=$Arguments[[Array]::IndexOf($Arguments,'--run')+1]
    $abi=$Arguments[[Array]::IndexOf($Arguments,'--abi')+1]
    # Use real capture/validation with a tiny pinned-archive fixture repository.
    & $global:AndroidLaunchPython -c 'import importlib.util,sys; from pathlib import Path; spec=importlib.util.spec_from_file_location("startup_identity",sys.argv[1]); module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module); module.capture(Path(sys.argv[2]),Path(sys.argv[3]),sys.argv[4],Path(sys.argv[5])); module.validate(Path(sys.argv[2]),Path(sys.argv[3]),sys.argv[4],Path(sys.argv[5]))' "$global:AndroidLaunchRepo/scripts/run/android-api21-identity.py" $root $run $abi $global:AndroidLaunchMediaRepo
    if ($LASTEXITCODE) { throw 'Actual startup identity capture failed on synthetic files' }
    $global:LASTEXITCODE=0
}
function Start-Process {
    param($FilePath,[string[]]$ArgumentList,$WindowStyle,[switch]$PassThru,$RedirectStandardOutput,$RedirectStandardError)
    if (!(Test-Path -LiteralPath ((Split-Path $RedirectStandardOutput)+'/emulator-identity.json'))) { throw 'Emulator started before identity capture' }
    $global:AndroidLaunchCalls.Add(@{file=$FilePath;arguments=@($ArgumentList);window=$WindowStyle})
    return [pscustomobject]@{Id=4242;HasExited=$false;ExitCode=0}
}
function Refuse-Launch([scriptblock]$Action,[string]$Message) {
    try { & $Action | Out-Null } catch { if ($_.Exception.Message -notmatch $Message) { throw };return }
    throw 'Expected launch refusal'
}
function Invoke-LaunchContender([string]$Root,[string]$Emulator) {
    $code="function docker { throw 'Unexpected Docker call' }; function python { throw 'Unexpected tool call' }; try { & '"+$RepoRoot.Replace("'","''")+"/scripts/run/qt6-android-start.ps1' -Abi armeabi-v7a -OutputDirectory '"+$Root.Replace("'","''")+"' -Emulator '"+$Emulator.Replace("'","''")+"' -RunName blocked-child; exit 2 } catch { if (`$_.Exception.Message -like 'Another Longreach operation*') { exit 0 }; Write-Error `$_; exit 3 }"
    $info=[Diagnostics.ProcessStartInfo]::new((Get-Command pwsh).Source)
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true
    foreach ($argument in @('-NoProfile','-EncodedCommand',[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code)))) { $info.ArgumentList.Add($argument) }
    $child=[Diagnostics.Process]::Start($info)
    try {
        if (!$child.WaitForExit(10000)) { throw 'Owned launch contender timed out' }
        if ($child.ExitCode -ne 0) { throw 'Starter did not reject the other process lease before tool calls' }
    } finally {
        if (!$child.HasExited) { $child.Kill();$null=$child.WaitForExit(5000) }
        $child.Dispose()
    }
}
try {
    New-Item -ItemType Directory -Force "$fixture/scripts/build/android-api21" | Out-Null
    Copy-Item -LiteralPath "$RepoRoot/scripts/build/android-api21/artifact-lock.ps1" -Destination "$fixture/scripts/build/android-api21/artifact-lock.ps1"
    New-Item -ItemType Directory -Force "$fixture/scripts/run" | Out-Null
    Copy-Item -LiteralPath "$RepoRoot/scripts/run/qt6-android-start.ps1" -Destination "$fixture/scripts/run/qt6-android-start.ps1"
    Copy-Item -LiteralPath "$RepoRoot/scripts/run/android-emulator-state.ps1" -Destination "$fixture/scripts/run/android-emulator-state.ps1"
    Copy-Item -LiteralPath "$RepoRoot/scripts/run/android-adb-endpoint.ps1" -Destination "$fixture/scripts/run/android-adb-endpoint.ps1"
    '. "$($global:AndroidOwnedFixture.Repo)/scripts/tests/android-owned-process-mock.ps1"' | Set-Content "$fixture/scripts/run/android-owned-process.ps1"
. "$RepoRoot/scripts/tests/android-owned-process-mock.ps1"
. "$RepoRoot/scripts/build/android-api21/artifact-lock.ps1"
    $root=(New-Item -ItemType Directory -Force "$fixture/output with spaces").FullName
    foreach ($abi in @('armeabi-v7a','arm64-v8a','x86','x86_64')) {
        & $global:AndroidLaunchPython -c 'import sys; from pathlib import Path; sys.path.insert(0,str(Path(sys.argv[1])/"scripts/tests")); import android_media_fixtures as fixture; fixture.archives(Path(sys.argv[2]),sys.argv[4]); fixture.media.prepare(Path(sys.argv[2]),Path(sys.argv[3]),sys.argv[4])' $RepoRoot $global:AndroidLaunchMediaRepo $root $abi
        if ($LASTEXITCODE) { throw 'Could not create small prepared-media fixture' }
        $emulator=switch ($abi) {
            'armeabi-v7a' { "$root/media/tools/emulator-arm.exe" }
            'arm64-v8a' { "$root/media/emulator-25.2.5/tools/emulator.exe" }
            default { "$root/media/emulator-32.1.11/emulator/emulator.exe" }
        }
        foreach ($gpu in @('on','mesa')) {
            $runName=('fixture-'+$abi+'-'+$gpu).Replace('_','-')
            [IO.File]::WriteAllText("$root/final-results.json",'old completed run')
            foreach ($busyName in @('qemu-system-armel-headless','qemu-system-aarch64-headless','qemu-system-mips64el')) {
                $global:AndroidLaunchBusyProcess=$busyName
                $before=$global:AndroidLaunchCalls.Count
                Refuse-Launch { & "$fixture/scripts/run/qt6-android-start.ps1" -Abi $abi -Gpu $gpu -OutputDirectory $root -Emulator $emulator -RunName $runName -PassThru } 'Another emulator is running'
                if ($global:AndroidLaunchCalls.Count -ne $before -or (Test-Path -LiteralPath "$root/$runName")) { throw 'Busy engine entered launch/run-data preparation' }
            }
            $global:AndroidLaunchBusyProcess=''
            $owned=& "$fixture/scripts/run/qt6-android-start.ps1" -Abi $abi -Gpu $gpu -OutputDirectory $root -Emulator $emulator -RunName $runName -PassThru
            if (Test-Path "$root/final-results.json") { throw 'Direct starter kept the prior aggregate PASS' }
            if ($global:AndroidLaunchCalls.Count -eq 1) {
                [IO.File]::WriteAllText("$root/final-results.json",'current active owner report')
                Refuse-Launch { & "$fixture/scripts/run/qt6-android-start.ps1" -Abi $abi -OutputDirectory $root -Emulator $emulator -RunName blocked-same } 'owned emulator still holds'
                Invoke-LaunchContender $root $emulator
                if ([IO.File]::ReadAllText("$root/final-results.json") -cne 'current active owner report') { throw 'Busy launch changed its owner report' }
                if ((Test-Path "$root/blocked-child") -or (Test-Path "$root/blocked-same")) { throw 'Busy launch created run data' }
            }
            $receipt=Get-Content -LiteralPath "$root/$runName/emulator-launch.json" -Raw | ConvertFrom-Json
            $actual=$global:AndroidLaunchCalls[$global:AndroidLaunchCalls.Count-1]
            $expectedGpu=if ($abi -in @('x86','x86_64')) { 'swiftshader_indirect' } else { $gpu }
            if ($receipt.abi -ne $abi -or $receipt.gpu_requested -ne $gpu -or $receipt.gpu_effective -ne $expectedGpu) { throw 'Wrong GPU receipt' }
            $index=[Array]::IndexOf($receipt.arguments,'-gpu')
            if ($index -lt 0 -or $receipt.arguments[$index+1] -ne $expectedGpu) { throw 'Receipt differs from actual GPU arguments' }
            $quoted=@($receipt.arguments)
            if (($quoted -join [char]0) -cne ($actual.arguments -join [char]0) -or $actual.file -cne $emulator) { throw 'Receipt differs from actual process invocation' }
            if ($actual.window -ne 'Hidden') { throw 'Startup did not request a hidden process' }
            Stop-AndroidOwnedProcess $owned | Out-Null
        }
    }
    # Restore the ARM fixture lock before its independent casing check.
    & $global:AndroidLaunchPython -c 'import sys; from pathlib import Path; sys.path.insert(0,str(Path(sys.argv[1])/"scripts/tests")); import android_media_fixtures as fixture; fixture.archives(Path(sys.argv[2]),"armeabi-v7a"); fixture.media.prepare(Path(sys.argv[2]),Path(sys.argv[3]),"armeabi-v7a")' $RepoRoot $global:AndroidLaunchMediaRepo $root
    if ($LASTEXITCODE) { throw 'Could not prepare casing fixture' }
    $emulator="$root/media/tools/emulator-arm.exe"
    & "$fixture/scripts/run/qt6-android-start.ps1" -Abi armeabi-v7a -Gpu ON -OutputDirectory $root -Emulator $emulator -RunName 'uppercase-gpu' | Out-Null
    $receipt=Get-Content -LiteralPath "$root/uppercase-gpu/emulator-launch.json" -Raw | ConvertFrom-Json
    if ($receipt.gpu_requested -cne 'on' -or $receipt.gpu_effective -cne 'on') { throw 'GPU option casing was not normalized before launch' }
    Stop-AndroidOwnedProcess (Get-AndroidOwnedProcess "$root/uppercase-gpu") | Out-Null
    [IO.File]::WriteAllText("$root/final-results.json",'prior report before failed preparation')
    [IO.File]::Delete("$root/media/armeabi-v7a/userdata.img")
    try { & "$fixture/scripts/run/qt6-android-start.ps1" -Abi armeabi-v7a -OutputDirectory $root -Emulator $emulator -RunName failed-preparation -ErrorAction Stop | Out-Null; throw 'Expected failed preparation' }
    catch { if ($_.Exception.Message -eq 'Expected failed preparation') { throw } }
    $free=Enter-AndroidArtifactLock $root
    if (!$free) { throw 'Failed startup retained its parent lease' }
    $free.Dispose()
    if ($global:AndroidLaunchCalls.Count -ne 9) { throw 'Not all ABI/GPU combinations were exercised' }
    Write-Output 'PASS: actual API21 identity capture precedes recorded launch; all four ABIs and both GPU requests'
} finally {
    if ($global:AndroidOwnedMockControls) {
        foreach ($control in $global:AndroidOwnedMockControls.Values) {
            if ($control.LeaseHandle) { $control.LeaseHandle.DangerousRelease();$control.LeaseHandle=$null }
        }
    }
    if (Test-Path -LiteralPath $fixture) {
        $resolved=(Resolve-Path -LiteralPath $fixture).Path
        if ([IO.Path]::GetDirectoryName($resolved) -ne $parent -or [IO.Path]::GetFileName($resolved) -notlike 'api21-launch-*') { throw 'Unexpected fixture cleanup path' }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
    Remove-Variable AndroidOwnedFixture,AndroidOwnedMockControls,AndroidLaunchRepo -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable AndroidLaunchBusyProcess,AndroidLaunchCalls,AndroidLaunchPython,AndroidLaunchMediaRepo -Scope Global -ErrorAction SilentlyContinue
}
