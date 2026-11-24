# SPDX-License-Identifier: GPL-3.0-or-later
# Actual probe body, ordinary metadata validator, recorded device/owner boundaries.
param([string]$RepoRoot=(Resolve-Path "$PSScriptRoot/../..").Path)
$ErrorActionPreference='Stop'
$parent=(New-Item -ItemType Directory -Force "$RepoRoot/build/fixtures").FullName
$fixture=Join-Path $parent ('android-probe-'+[guid]::NewGuid())
$global:AndroidProbeFixture=@{Repo=$RepoRoot;Python=(Get-Command python -CommandType Application | Select-Object -First 1).Source;
    Calls=[Collections.Generic.List[string]]::new();Mode='';Owner=$null;Root='';Started=$false;Stopped=$false;Busy=$false}
function Assert-Probe([bool]$Value,[string]$Reason) { if (!$Value) { throw $Reason } }
function python {
    $context=$global:AndroidProbeFixture
    if ([IO.Path]::GetFileName([string]$args[0]) -eq 'prepare-emulator.py') {
        $context.Calls.Add('prepare')
        $global:LASTEXITCODE=if ($context.Mode -eq 'prepare-failed') { 1 } else { 0 }
        return
    }
    $validator=[IO.Path]::GetFileName([string]$args[0])
    if ($validator -notin @('require-modern-cpp.py','require-android-atomic.py')) { throw 'Unexpected Python tool' }
    & $context.Python "$($context.Repo)/scripts/tests/$validator" @($args | Select-Object -Skip 1)
}
try {
    foreach ($relative in @('scripts/run/qt6-android-probe.ps1','scripts/build/android-api21/artifact-lock.ps1')) {
        $target=Join-Path $fixture $relative
        New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
        Copy-Item -LiteralPath (Join-Path $RepoRoot $relative) -Destination $target
    }
    Copy-Item -LiteralPath "$RepoRoot/scripts/run/android-shell-status.ps1" -Destination "$fixture/scripts/run/android-shell-status.ps1"
    New-Item -ItemType Directory -Force "$fixture/scripts/fetch" | Out-Null
    @'
param($Scope,$Abi,$AndroidSdk)
$global:AndroidProbeFixture.Calls.Add('fetch')
Get-AndroidArtifactLockStream $global:AndroidProbeFixture.Root | Out-Null
'@ | Set-Content "$fixture/scripts/fetch/qt6-android.ps1"
    @'
function Assert-AndroidOwnedArtifactRootAvailable($Root) {
    if ($global:AndroidProbeFixture.Busy) { throw 'Recorded active root owner' }
}
function Stop-AndroidOwnedProcess($Control) {
    if (![object]::ReferenceEquals($Control,$global:AndroidProbeFixture.Owner)) { throw 'Wrong retained control' }
    $global:AndroidProbeFixture.Stopped=$true
    $Control.Process=$null
}
'@ | Set-Content "$fixture/scripts/run/android-owned-process.ps1"
    @'
param($OutputDirectory,$Emulator,$RunName,$Abi,[switch]$PassThru)
if (!$PassThru) { throw 'Probe did not request retained owner' }
Get-AndroidArtifactLockStream $OutputDirectory | Out-Null
New-Item -ItemType Directory "$OutputDirectory/$RunName" | Out-Null
$global:AndroidProbeFixture.Started=$true
$global:AndroidProbeFixture.Owner=[pscustomobject]@{Process=[pscustomobject]@{Id=1234};Owner=[pscustomobject]@{frontend_pid=5678}}
return $global:AndroidProbeFixture.Owner
'@ | Set-Content "$fixture/scripts/run/qt6-android-start.ps1"
    @'
function Wait-AndroidBoot($Adb,$Serial,$RunDirectory,$EmulatorPid,$EmulatorProcess) {
    if ($EmulatorPid -ne 1234 -or ![object]::ReferenceEquals($EmulatorProcess,$global:AndroidProbeFixture.Owner.Process)) { throw 'Boot lacks retained supervisor' }
    if ($global:AndroidProbeFixture.Mode -eq 'boot-failed') { throw 'Recorded boot failure' }
}
'@ | Set-Content "$fixture/scripts/run/android-wait-boot.ps1"
    @'
function Invoke-AndroidApi21Adb {
    param($Adb,$Serial,[string[]]$Parameters,[int]$TimeoutMilliseconds)
    $context=$global:AndroidProbeFixture
    if ($Serial -cne 'emulator-5582' -or $Adb.Replace('\','/') -notlike '*/platform-tools/adb.exe') { throw 'Wrong device boundary' }
    $context.Calls.Add($Parameters -join '|')
    $global:LASTEXITCODE=0
    if ($Parameters[0] -eq 'push') {
        if ($context.Mode -eq 'push-timeout') { throw 'Recorded push timeout' }
        return 'recorded transfer'
    }
    if (($Parameters -join '|') -like 'shell|getprop|*') {
        switch ($Parameters[2]) {
            'ro.build.version.sdk' { return '21' }
            'ro.build.version.release' { return '5.0.2' }
            'ro.product.cpu.abi' { return $context.Abi }
            default { throw 'Unexpected property' }
        }
    }
    $step=''
    if ($Parameters[0] -eq 'shell') {
        $command=$Parameters -join ' '
        if ($command -match '(?:^|[ (])mkdir -p /data/local/tmp/longreach-cxx23-') { $step='mkdir' }
        elseif ($command -match 'chmod 755 /data/local/tmp/longreach-cxx23-[a-z0-9_-]+/cxx23-probe') { $step='cxx23-chmod' }
        elseif ($command -match 'chmod 755 /data/local/tmp/longreach-cxx23-[a-z0-9_-]+/atomic-probe') { $step='atomic-chmod' }
    }
    if ($step) {
        $fault=if ($context.Mode.StartsWith("setup-$step/")) { $context.Mode.Substring("setup-$step/".Length) } else { '' }
        if ($fault -eq 'timeout') { throw 'Recorded setup timeout' }
        if ($fault -eq 'client-failed') { throw 'Recorded setup client failure' }
        # The old unwrapped API21 path loses the remote command status.
        if ($Parameters.Count -ne 2 -or $Parameters[1] -notmatch 'LONGREACH_SHELL_[a-f0-9]{32}') {
            if ($fault) { return 'recorded remote permission denied (host status zero)' }
            return
        }
        if ($TimeoutMilliseconds -ne 15000) { throw 'Setup has no explicit bounded budget' }
        $marker=$Matches[0]
        switch ($fault) {
            'nonzero' { 'recorded permission denied';"${marker}:7";return }
            'missing' { return 'recorded output without a status' }
            'duplicate' { "${marker}:0";"${marker}:0";return }
            'malformed' { "${marker}:00";return }
            'stale' { 'LONGREACH_SHELL_00000000000000000000000000000000:0';return }
            default { "${marker}:0";return }
        }
    }
    if ($Parameters[0] -eq 'shell' -and $Parameters.Count -eq 2 -and $Parameters[1] -like '*./cxx23-probe;*') {
        if ($TimeoutMilliseconds -ne 180000) { throw 'Native probe has no explicit budget' }
        if ($context.Mode -eq 'probe-timeout') { throw 'Recorded native probe timeout' }
        '__cplusplus: 202302'
        $names=@(Get-Content "$($context.Repo)/tests/common/moderncpp-required.txt" | Where-Object { $_ -and !($_.StartsWith('#')) })
        $names | ForEach-Object { 'PASS: '+$_ }
        "SUMMARY: $($names.Count) passed, 0 failed, 0 skipped"
        'PROBE_EXIT:0'
        return
    }
    if ($Parameters[0] -eq 'shell' -and $Parameters.Count -eq 2 -and $Parameters[1] -like '*./atomic-probe;*') {
        if ($TimeoutMilliseconds -ne 180000) { throw 'Atomic probe has no explicit budget' }
        if ($context.Mode -eq 'atomic-timeout') { throw 'Recorded atomic probe timeout' }
        if ($context.Mode -eq 'atomic-old-output') {
            'PASS: generic 16-byte atomic store/load/exchange/CAS/thread handoff';'ATOMIC_EXIT:0';return
        }
        if ($context.Mode -ne 'atomic-missing-provider') {
            if ($context.Mode -eq 'atomic-wrong-provider') { 'ATOMIC_PROVIDER: libother.so' }
            else { 'ATOMIC_PROVIDER: libc++_shared.so' }
        }
        if ($context.Mode -eq 'atomic-one-worker') { 'ATOMIC_WORKERS: 1' } else { 'ATOMIC_WORKERS: 2' }
        if ($context.Mode -eq 'atomic-reported-failure') { 'FAIL: cross-DSO handoff' }
        'PASS: generic 24-byte cross-DSO atomic store/load/exchange/CAS/thread handoff'
        if ($context.Mode -eq 'atomic-nonzero-exit') { 'ATOMIC_EXIT:7' } else { 'ATOMIC_EXIT:0' }
        if ($context.Mode -eq 'atomic-duplicate-exit') { 'ATOMIC_EXIT:0' }
    }
}
'@ | Set-Content "$fixture/scripts/run/android-api21-adb.ps1"
    @'
param($Adb,$Serial,$RunDirectory,$EmulatorPid)
if ($EmulatorPid -ne 5678) { throw 'Cleanup used mutable PID file or supervisor PID' }
if ($global:AndroidProbeFixture.Mode -eq 'cleanup-failed') { throw 'Recorded cleanup lookup failure' }
Stop-AndroidOwnedProcess $global:AndroidProbeFixture.Owner
'@ | Set-Content "$fixture/scripts/run/android-api21-cleanup.ps1"
    $cases=@()
    foreach ($abi in @('armeabi-v7a','arm64-v8a','x86','x86_64')) {
        foreach ($mode in @('ready','push-timeout','probe-timeout','atomic-timeout','atomic-old-output','atomic-missing-provider','atomic-wrong-provider','atomic-one-worker','atomic-duplicate-exit','atomic-nonzero-exit','atomic-reported-failure')) { $cases+=@{Abi=$abi;Mode=$mode} }
    }
    foreach ($mode in @('prepare-failed','boot-failed','cleanup-failed','locked','busy','invalid-name')) { $cases+=@{Abi='x86';Mode=$mode} }
    foreach ($abi in @('armeabi-v7a','arm64-v8a','x86','x86_64')) {
        foreach ($step in @('mkdir','cxx23-chmod','atomic-chmod')) {
            foreach ($fault in @('nonzero','missing','duplicate','malformed','stale','client-failed','timeout')) {
                $cases+=@{Abi=$abi;Mode="setup-$step/$fault"}
            }
        }
    }

    foreach ($abi in @('armeabi-v7a','arm64-v8a','x86','x86_64')) {
        foreach ($side in @('a','b')) { $cases+=@{Abi=$abi;Mode="missing-worker-$side"} }
    }
    $index=0
    foreach ($case in $cases) {
        $index++
        $context=$global:AndroidProbeFixture
        $context.Mode=$case.Mode;$context.Abi=$case.Abi;$context.Started=$false;$context.Stopped=$false
        $context.Owner=$null;$context.Calls.Clear();$context.Busy=$case.Mode -eq 'busy'
        $root=Join-Path $fixture "out-$index"
        $context.Root=$root
        New-Item -ItemType Directory -Force "$root/probe" | Out-Null
        $inputs=@('cxx23-probe','libc++_shared.so','atomic-probe','liblongreach-atomic-a.so','liblongreach-atomic-b.so')
        foreach ($name in $inputs) { "data for $name, never executed" | Set-Content "$root/probe/$name" }
        if ($case.Mode -like 'missing-worker-*') {
            $side=$case.Mode.Substring('missing-worker-'.Length)
            [IO.File]::Delete("$root/probe/liblongreach-atomic-$side.so")
        }
        'old report' | Set-Content "$root/final-results.json"
        $lock=$null
        try {
            if ($case.Mode -eq 'locked') { $lock=[IO.File]::Open("$root/.longreach-artifacts.lock",'OpenOrCreate','ReadWrite','None') }
            $runName=if ($case.Mode -eq 'invalid-name') { '../bad' } else { 'probe-run' }
            $errorText=$null
            try {
                & "$fixture/scripts/run/qt6-android-probe.ps1" -Abi $case.Abi -AndroidSdk "$fixture/sdk" -OutputDirectory $root -RunName $runName | Out-Null
            } catch { $errorText=$_.Exception.Message }
            if ($case.Mode -eq 'ready') {
                Assert-Probe (!$errorText -and $context.Stopped) "Normal probe failed: $errorText"
                $records=@(Get-Content -LiteralPath "$root/probe-run/probe-inputs.json" -Raw | ConvertFrom-Json)
                Assert-Probe ($records.Count -eq 5 -and (@($records.file | Sort-Object -Unique).Count -eq 5)) 'Not every probe input was recorded'
                foreach ($name in $inputs) {
                    $entry=@($records | Where-Object file -CEQ $name)
                    $sha=(Get-FileHash -LiteralPath "$root/probe/$name" -Algorithm SHA256).Hash.ToLowerInvariant()
                    Assert-Probe ($entry.Count -eq 1 -and $entry[0].sha256 -ceq $sha) 'Wrong current probe input hash'
                    Assert-Probe (@($context.Calls | Where-Object { $_ -ceq "push|$root/probe/$name|/data/local/tmp/longreach-cxx23-$($case.Abi)/$name" }).Count -eq 1) 'Probe input was not transferred once'
                }
                Assert-Probe (@($context.Calls | Where-Object { $_ -like '*./atomic-probe;*' }).Count -eq 1) 'ABI did not execute exactly one recorded atomic stage'
            }
            else {
                $expected=switch ($case.Mode) {
                    'push-timeout' { 'push timeout' };'probe-timeout' { 'native probe timeout' };'atomic-timeout' { 'atomic probe timeout' }
                    'prepare-failed' { 'Could not prepare' };'boot-failed' { 'boot failure' };'cleanup-failed' { 'cleanup lookup failure' }
                    'locked' { 'Another Longreach operation' };'busy' { 'active root owner' };'invalid-name' { 'Invalid run directory' }
                }
                if ($case.Mode -like 'atomic-*' -and $case.Mode -ne 'atomic-timeout') { $expected='Generic cross-DSO atomic runtime behavior failed' }
                if ($case.Mode -like 'missing-worker-*') { $expected='Missing .*liblongreach-atomic' }
                if ($case.Mode -like 'setup-*') {
                    $expected=switch ($case.Mode.Split('/')[1]) {
                        'nonzero' { 'Remote Android setup .* failed with status 7' }
                        'client-failed' { 'Recorded setup client failure' }
                        'timeout' { 'Recorded setup timeout' }
                        default { 'Missing or invalid Android setup status marker' }
                    }
                }
                Assert-Probe ($errorText -match $expected) "Unexpected $($case.Mode) outcome: $errorText"
            }
            if ($case.Mode -like 'setup-*') {
                $step=($case.Mode.Split('/')[0]).Substring(6)
                $nativeCalls=@($context.Calls | Where-Object { $_ -like '*./cxx23-probe;*' -or $_ -like '*./atomic-probe;*' })
                $expectedNativeCalls=if ($step -eq 'atomic-chmod') { 1 } else { 0 }
                Assert-Probe ($nativeCalls.Count -eq $expectedNativeCalls) 'A failed setup entered a later native stage'
                if ($step -eq 'mkdir') { Assert-Probe (@($context.Calls | Where-Object { $_ -like 'push|*' }).Count -eq 0) 'A failed mkdir still transferred binaries' }
                Assert-Probe (Test-Path -LiteralPath "$root/probe-run/setup-$step.stdout") 'Setup failure has no current diagnostic file'
                if ($case.Mode -like '*/timeout' -or $case.Mode -like '*/client-failed') {
                    Assert-Probe ((Get-Item -LiteralPath "$root/probe-run/setup-$step.stdout").Length -eq 0) 'Failed ADB request retained a success transcript'
                }
            }
            if ($context.Started) { Assert-Probe $context.Stopped 'Probe failure leaked retained owner' }
            if ($case.Mode -in @('locked','busy','invalid-name') -or $case.Mode -like 'missing-worker-*') {
                Assert-Probe ($context.Calls.Count -eq 0 -and (Get-Content "$root/final-results.json") -ceq 'old report') 'Refused preflight changed active reports or used a tool'
            } else { Assert-Probe (!(Test-Path "$root/final-results.json")) 'Old full report survived diagnostic probe' }
        } finally { if ($lock) { $lock.Dispose() } }
        $check=[IO.File]::Open("$root/.longreach-artifacts.lock",'OpenOrCreate','ReadWrite','None')
        $check.Dispose()
    }
    Write-Output "PASS: $($cases.Count) recorded probe paths, four ABIs, actual modern-output validator, deadlines, root preservation/release and retained-owner cleanup; no device executes"
} finally {
    Remove-Variable AndroidProbeFixture -Scope Global -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $fixture) {
        $resolved=(Resolve-Path -LiteralPath $fixture).Path
        if ([IO.Path]::GetDirectoryName($resolved) -ne $parent -or [IO.Path]::GetFileName($resolved) -notlike 'android-probe-*') { throw 'Unexpected fixture cleanup path' }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
