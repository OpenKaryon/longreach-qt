# SPDX-License-Identifier: GPL-3.0-or-later
. "$($global:AndroidOwnedFixture.Repo)/scripts/run/android-adb-endpoint.ps1"
# Recording fixtures only. Context supplies the real Python and repository root.
function New-AndroidOwnedMockProcess([int]$ProcessId=4242) {
    $object=[pscustomobject]@{Id=$ProcessId;HasExited=$false;ExitCode=0}
    $object | Add-Member ScriptMethod Refresh { }
    $object | Add-Member ScriptMethod WaitForExit { param($Milliseconds);return $this.HasExited }
    $object | Add-Member ScriptMethod Dispose { }
    return $object
}
function Assert-AndroidOwnedArtifactRootAvailable([string]$Root) {
    if ($global:AndroidOwnedMockControls) {
        foreach ($control in $global:AndroidOwnedMockControls.Values) {
            if ($control.ArtifactRoot -and [IO.Path]::GetFullPath($control.ArtifactRoot) -eq [IO.Path]::GetFullPath($Root) -and
                    $control.Process -and !$control.Process.HasExited) { throw 'Another owned emulator still holds this artifact root' }
        }
    }
}
function Start-AndroidOwnedProcess {
    param($Program,[string[]]$Arguments,$Directory,$WorkingDirectory,$StartupTimeoutMilliseconds,$ArtifactLease,$ArtifactRoot,$AdbEndpoint)
    if ($global:AndroidOwnedFixture.RecordStart) {
        $process=Start-Process -FilePath $Program -ArgumentList $Arguments -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput "$Directory/emulator.stdout" -RedirectStandardError "$Directory/emulator.stderr"
    } else { $process=New-AndroidOwnedMockProcess }
    @{program=$Program;arguments=@($Arguments);supervisor_pid=$process.Id;frontend_pid=$process.Id+1;artifact_root=$ArtifactRoot;adb_endpoint=$AdbEndpoint} |
        ConvertTo-Json -Depth 5 | Set-Content "$Directory/host-process-fixture-start.json"
    & $global:AndroidOwnedFixture.Python "$($global:AndroidOwnedFixture.Repo)/scripts/tests/android_owned_process_fixtures.py" capture --directory $Directory --spec "$Directory/host-process-fixture-start.json" | Out-Null
    if ($LASTEXITCODE) { throw 'Data-only host receipt fixture failed' }
    $leaseHandle=$null
    if ($ArtifactLease) {
        $leaseHandle=$ArtifactLease.SafeFileHandle
        $added=$false
        $leaseHandle.DangerousAddRef([ref]$added)
        if (!$added) { throw 'Recording lease retention failed' }
    }
    $control=[pscustomobject]@{Directory=$Directory;Process=$process;ArtifactRoot=$ArtifactRoot;LeaseHandle=$leaseHandle;
        Owner=(Get-Content "$Directory/host-process-owner.json" -Raw | ConvertFrom-Json);
        OwnerSha=(Get-FileHash "$Directory/host-process-owner.json").Hash.ToLowerInvariant();
        Request=(Get-Content "$Directory/host-process-request.json" -Raw | ConvertFrom-Json);
        RequestSha=(Get-FileHash "$Directory/host-process-request.json").Hash.ToLowerInvariant()}
    if ($AdbEndpoint) { Set-AndroidAdbEndpointContext -Directory $Directory -Endpoint $AdbEndpoint -RequestSha $control.RequestSha }
    if (!$global:AndroidOwnedMockControls) { $global:AndroidOwnedMockControls=@{} }
    $global:AndroidOwnedMockControls[$Directory]=$control
    return $control
}
function Get-AndroidOwnedProcess([string]$Directory) {
    if ($global:AndroidOwnedMockControls -and $global:AndroidOwnedMockControls.ContainsKey($Directory)) { return $global:AndroidOwnedMockControls[$Directory] }
    return [pscustomobject]@{Directory=$Directory;Process=(New-AndroidOwnedMockProcess);
        Owner=(Get-Content "$Directory/host-process-owner.json" -Raw | ConvertFrom-Json);
        OwnerSha=(Get-FileHash "$Directory/host-process-owner.json").Hash.ToLowerInvariant();
        RequestSha=(Get-FileHash "$Directory/host-process-request.json").Hash.ToLowerInvariant()}
}
function Stop-AndroidOwnedProcess {
    param($Control,$GraceMilliseconds)
    if ($Control.Process) { $Control.Process.HasExited=$true }
    Clear-AndroidAdbEndpointContext $Control.Directory -RequestSha $Control.RequestSha
    if ($Control.LeaseHandle) { $Control.LeaseHandle.DangerousRelease();$Control.LeaseHandle=$null }
    $json=@(& $global:AndroidOwnedFixture.Python "$($global:AndroidOwnedFixture.Repo)/scripts/tests/android_owned_process_fixtures.py" finish --directory $Control.Directory)
    if ($LASTEXITCODE) { throw 'Data-only host completion fixture failed' }
    return ($json -join "`n" | ConvertFrom-Json)
}
function Write-AndroidOwnedProcessJson([string]$Path,$Value) {
    $Value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path
}
