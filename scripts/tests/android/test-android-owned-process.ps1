# SPDX-License-Identifier: GPL-3.0-or-later
# Ordinary hidden Python children and real PS/native owner interface, no Android.
param([string]$RepoRoot=(Resolve-Path "$PSScriptRoot/../../..").Path)
$ErrorActionPreference='Stop'
$global:OwnedSerialEmulatorStops=0
if (!$IsWindows) { Write-Output 'SKIP: native owned-process interface requires Windows 10+';return }
. "$RepoRoot/scripts/run/android/android-owned-process.ps1"
$python=(Get-Command python -CommandType Application | Select-Object -First 1).Source
$parent=(New-Item -ItemType Directory -Force "$RepoRoot/build/fixtures").FullName
$fixture=Join-Path $parent ('owned-process-interface-'+[guid]::NewGuid())
$active=[Collections.Generic.List[object]]::new()
$other=$null
$artifactStream=$null
function Assert-Owned([bool]$Condition,[string]$Message) { if (!$Condition) { throw $Message } }
function Refuse-Owned([scriptblock]$Action,[string]$Pattern) {
    try { & $Action | Out-Null } catch { Assert-Owned ($_.Exception.Message -match $Pattern) "Unexpected owner refusal: $_";return }
    throw 'Expected owned-process refusal'
}
function New-OwnedDirectory([string]$Name) { (New-Item -ItemType Directory -Path (Join-Path $fixture $Name)).FullName }
try {
    New-Item -ItemType Directory -Path $fixture | Out-Null
    $directory=New-OwnedDirectory 'exact args with spaces'
    $arguments=@('two words','embedded"quote','trailing\','кириллица')
    $control=Start-AndroidOwnedProcess -Program $python -Arguments (@('-c','import json,sys; print(json.dumps(sys.argv[1:],ensure_ascii=True))')+$arguments) -Directory $directory
    $active.Add($control)
    $proof=Stop-AndroidOwnedProcess $control -GraceMilliseconds 0
    $active.Remove($control) | Out-Null
    Assert-Owned ($proof.host_process_exit_sha256 -match '^[0-9a-f]{64}$') 'PS/native final proof missing'
    Assert-Owned (((Get-Content "$directory/emulator.stdout" -Raw | ConvertFrom-Json) -join [char]0) -ceq ($arguments -join [char]0)) 'PS interface changed unquoted arguments'
    $completed=Get-AndroidOwnedProcess $directory
    Assert-Owned ($null -eq $completed.Process) 'Completed receipt attached a numeric PID'
    Stop-AndroidOwnedProcess $completed -GraceMilliseconds 0 | Out-Null

    $directory=New-OwnedDirectory 'descendant'
    $child="import time; time.sleep(30)"
    $code="import subprocess,sys; subprocess.Popen([sys.executable,'-c',"+($child | ConvertTo-Json -Compress)+"],creationflags=0x08000000)"
    $control=Start-AndroidOwnedProcess -Program $python -Arguments @('-c',$code) -Directory $directory
    $active.Add($control)
    Assert-Owned (!$control.Process.HasExited) 'Frontend exit lost its child tree'
    $before=[IO.File]::ReadAllText("$directory/host-process-request.json")
    Refuse-Owned { Start-AndroidOwnedProcess -Program $python -Arguments @('-c','pass') -Directory $directory } 'fresh owned-process'
    Assert-Owned ([IO.File]::ReadAllText("$directory/host-process-request.json") -ceq $before) 'Contender replaced an active request'
    Stop-AndroidOwnedProcess $control -GraceMilliseconds 0 | Out-Null
    $active.Remove($control) | Out-Null
    $receipt=Get-Content "$directory/host-process-exit.json" -Raw | ConvertFrom-Json
    Assert-Owned ($receipt.active_processes -eq 0 -and $receipt.total_processes -ge 2) 'Descendant tree was not confirmed empty'

    $directory=New-OwnedDirectory 'reattach'
    $control=Start-AndroidOwnedProcess -Program $python -Arguments @('-c','import time; time.sleep(30)') -Directory $directory
    $active.Add($control)
    $null=$global:LongreachOwnedProcesses.Remove($directory)
    $attached=Get-AndroidOwnedProcess $directory
    $active.Add($attached)
    Assert-Owned ($attached.Process.Id -eq $control.Process.Id) 'Reattachment changed process identity'
    Stop-AndroidOwnedProcess $attached -GraceMilliseconds 0 | Out-Null
    $active.Remove($attached) | Out-Null
    $control.Process.Dispose();$active.Remove($control) | Out-Null

    $directory=New-OwnedDirectory 'pid identity'
    $control=Start-AndroidOwnedProcess -Program $python -Arguments @('-c','import time; time.sleep(30)') -Directory $directory
    $active.Add($control)
    $info=[Diagnostics.ProcessStartInfo]::new($python)
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true
    foreach ($arg in @('-c','import time; time.sleep(30)')) { $info.ArgumentList.Add($arg) }
    $other=[Diagnostics.Process]::Start($info)
    $ownerPath=Join-Path $directory 'host-process-owner.json'
    $ownerBytes=[IO.File]::ReadAllBytes($ownerPath)
    try {
        $owner=Get-Content $ownerPath -Raw | ConvertFrom-Json
        $owner.supervisor_pid=$other.Id;$owner.supervisor_creation_filetime='1'
        Write-AndroidOwnedProcessJson $ownerPath $owner
        $null=$global:LongreachOwnedProcesses.Remove($directory)
        Refuse-Owned { Get-AndroidOwnedProcess $directory } 'reused supervisor PID'
        Assert-Owned (!$other.HasExited) 'Identity refusal stopped an unrelated process'
    } finally { [IO.File]::WriteAllBytes($ownerPath,$ownerBytes) }
    Stop-AndroidOwnedProcess $control -GraceMilliseconds 0 | Out-Null
    $active.Remove($control) | Out-Null
    $cleanupScripts=(New-Item -ItemType Directory -Force "$fixture/cleanup-scripts").FullName
    Copy-Item -LiteralPath "$RepoRoot/scripts/run/android/android-api21-cleanup.ps1" -Destination "$cleanupScripts/android-api21-cleanup.ps1"
    '. "'+$RepoRoot+'/scripts/run/android/android-owned-process.ps1"' | Set-Content "$cleanupScripts/android-owned-process.ps1"
    @'
function Invoke-AndroidExitQuery {
    param($Adb,$Serial,$Command,$Directory,$Name,$TimeoutMilliseconds,[switch]$AllowNonzero)
    if ($Command -contains 'emu') { $global:OwnedSerialEmulatorStops++;throw 'Fixture: serial-based emulator termination must not run' }
    throw 'Controlled ADB query timeout, no ADB executable runs'
}
'@ | Set-Content "$cleanupScripts/android-process-exit.ps1"
    $directory=New-OwnedDirectory 'common-cleanup'
    $control=Start-AndroidOwnedProcess -Program $python -Arguments @('-c','import time; time.sleep(30)') -Directory $directory
    $active.Add($control)
    $proof=& "$cleanupScripts/android-api21-cleanup.ps1" -Adb 'data-only-adb.exe' -RunDirectory $directory -EmulatorPid $control.Owner.frontend_pid -GraceMilliseconds 0
    $active.Remove($control) | Out-Null
    Assert-Owned ($proof.host_process_exit_sha256 -match '^[0-9a-f]{64}$') 'Common cleanup did not return verified tree completion'
    Assert-Owned (@(Get-Content "$directory/cleanup.log").Count -eq 1) 'Failed final log query did not reach owned shutdown'
    . "$RepoRoot/scripts/run/android/android-wait-boot.ps1"
    $directory=New-OwnedDirectory 'dead monitor'
    $control=Start-AndroidOwnedProcess -Program $python -Arguments @('-c','pass') -Directory $directory
    $active.Add($control)
    Assert-Owned ($control.Process.WaitForExit(5000)) 'Short supervisor did not complete'
    Refuse-Owned { Wait-AndroidBoot -Adb 'data-only-adb.exe' -RunDirectory $directory -EmulatorPid $PID -EmulatorProcess $control.Process } 'Owned emulator tree exited'
    Stop-AndroidOwnedProcess $control -GraceMilliseconds 0 | Out-Null
    $active.Remove($control) | Out-Null

    $broken=(New-Item -ItemType Directory -Path "$fixture/broken-helper").FullName
    Copy-Item -LiteralPath "$RepoRoot/scripts/run/android/android-owned-process.ps1" -Destination "$broken/android-owned-process.ps1"
    Copy-Item -LiteralPath "$RepoRoot/scripts/run/android/android-adb-endpoint.ps1" -Destination "$broken/android-adb-endpoint.ps1"
    try {
        . "$broken/android-owned-process.ps1"
        $directory=New-OwnedDirectory 'missing supervisor script'
        Refuse-Owned { Start-AndroidOwnedProcess -Program $python -Arguments @('-c','pass') -Directory $directory } 'Could not own host process'
        Assert-Owned (!(Test-Path "$directory/emulator.stdout")) 'Failed startup reached frontend creation'
        Assert-Owned (Test-Path "$directory/emulator-supervisor.stderr") 'Failed supervisor diagnostics lost'
        'import time; time.sleep(30)' | Set-Content "$broken/android-owned-process.py"
        $directory=New-OwnedDirectory 'supervisor handshake timeout'
        Refuse-Owned { Start-AndroidOwnedProcess -Program $python -Arguments @('-c','pass') -Directory $directory -StartupTimeoutMilliseconds 100 } 'Could not own host process'
        Assert-Owned (!(Test-Path "$directory/host-process-owner.json")) 'Handshake timeout invented an owner'
        Assert-Owned (!$global:LongreachOwnedProcesses.ContainsKey($directory)) 'Failed startup retained its registry entry'
    } finally { . "$RepoRoot/scripts/run/android/android-owned-process.ps1" }
    . "$RepoRoot/scripts/build/android-api21/artifact-lock.ps1"
    $artifactRoot=New-OwnedDirectory 'lease-root'
    $directory=(New-Item -ItemType Directory -Path "$artifactRoot/run").FullName
    $artifactStream=Enter-AndroidArtifactLock $artifactRoot
    $control=Start-AndroidOwnedProcess -Program $python -Arguments @('-c','import time; time.sleep(30)') -Directory $directory -ArtifactRoot $artifactRoot -ArtifactLease $artifactStream
    $active.Add($control)
    $artifactStream.Dispose();$artifactStream=$null
    Refuse-Owned { Enter-AndroidArtifactLock $artifactRoot } 'Another Longreach operation'
    $blocked=@(& $python "$RepoRoot/scripts/build/android-api21/artifact-manifest.py" begin --root $artifactRoot --qt-major 6 --abi x86_64 --sdk-image-id ('sha256:'+('a'*64)) 2>&1)
    Assert-Owned ($LASTEXITCODE -ne 0 -and ($blocked -join "`n") -match 'Another Longreach operation') 'Python producer entered the transferred lease'
    Assert-Owned (!(Test-Path "$artifactRoot/examples-in-progress.json")) 'Blocked producer reserved a generation'
    $peerCode='. "'+$RepoRoot.Replace('"','`"')+'/scripts/run/android/android-owned-process.ps1"; Stop-AndroidOwnedProcess (Get-AndroidOwnedProcess "'+$directory.Replace('"','`"')+'") -GraceMilliseconds 0 | Out-Null'
    $peerInfo=[Diagnostics.ProcessStartInfo]::new((Get-Command pwsh).Source)
    $peerInfo.UseShellExecute=$false;$peerInfo.CreateNoWindow=$true
    foreach ($argument in @('-NoProfile','-EncodedCommand',[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($peerCode)))) { $peerInfo.ArgumentList.Add($argument) }
    $peer=[Diagnostics.Process]::Start($peerInfo)
    try {
        if (!$peer.WaitForExit(15000) -or $peer.ExitCode -ne 0) { throw 'Independent cleanup could not stop the leased tree' }
    } finally { if (!$peer.HasExited) { Stop-AndroidOwnedSupervisorHandle $peer };$peer.Dispose() }
    $proof=Stop-AndroidOwnedProcess $control -GraceMilliseconds 0
    $active.Remove($control) | Out-Null
    $artifactStream=Enter-AndroidArtifactLock $artifactRoot
    Assert-Owned ($null -ne $artifactStream) 'Tree completion did not release its lease'
    $artifactStream.Dispose();$artifactStream=$null
    $exit=Get-Content "$directory/host-process-exit.json" -Raw | ConvertFrom-Json
    Assert-Owned $exit.artifact_lease_held_until_exit 'Completed tree omitted lease lifetime proof'
    Assert-Owned ($global:OwnedSerialEmulatorStops -eq 0) 'Serial-based emulator termination was attempted'
    Write-Output 'PASS: real PS ownership interface, exact argv, descendant cleanup, duplicate refusal, completed/active attachment and PID creation-time protection'
} catch {
    foreach ($name in @('host-process-failed.json','emulator-supervisor.stderr')) {
        Get-ChildItem -LiteralPath $fixture -Recurse -Filter $name -ErrorAction SilentlyContinue | ForEach-Object {
            Get-Content -LiteralPath $_.FullName | Write-Output
        }
    }
    throw
} finally {
    foreach ($control in $active) {
        try { Stop-AndroidOwnedSupervisorHandle $control.Process }
        finally { if ($control.Process) { $control.Process.Dispose() } }
    }
    if ($artifactStream) { $artifactStream.Dispose() }
    if ($other) { try { Stop-AndroidOwnedSupervisorHandle $other } finally { $other.Dispose() } }
    if (Test-Path -LiteralPath $fixture) {
        $resolved=(Resolve-Path -LiteralPath $fixture).Path
        if ([IO.Path]::GetDirectoryName($resolved) -ne $parent -or [IO.Path]::GetFileName($resolved) -notlike 'owned-process-interface-*') { throw 'Unexpected owned-process fixture cleanup path' }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
    Remove-Variable OwnedSerialEmulatorStops -Scope Global -ErrorAction SilentlyContinue
}
