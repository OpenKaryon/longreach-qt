# SPDX-License-Identifier: GPL-3.0-or-later
. "$PSScriptRoot/android-adb-endpoint.ps1"
# A process handle and creation time identify the supervisor, never a PID alone.
function Get-AndroidOwnedProcessKey([string]$Directory) {
    [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Directory))
}
function Initialize-AndroidOwnedProcessRegistry {
    if ($global:LongreachOwnedProcesses -isnot [Collections.Generic.Dictionary[string,object]]) {
        $comparer=if ($IsWindows) { [StringComparer]::OrdinalIgnoreCase } else { [StringComparer]::Ordinal }
        $global:LongreachOwnedProcesses=[Collections.Generic.Dictionary[string,object]]::new($comparer)
    }
}
function Assert-AndroidOwnedArtifactRootAvailable([string]$Root) {
    $key=Get-AndroidOwnedProcessKey $Root
    Initialize-AndroidOwnedProcessRegistry
    foreach ($control in $global:LongreachOwnedProcesses.Values) {
        if ($control.ArtifactRoot -and (Get-AndroidOwnedProcessKey $control.ArtifactRoot) -eq $key -and
                $control.Process -and !$control.Process.HasExited) { throw 'Another owned emulator still holds this artifact root' }
    }
}
function Write-AndroidOwnedProcessJson([string]$Path,$Value) {
    $temporary=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try {
        [IO.File]::WriteAllText($temporary,($Value | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporary,$Path,$true)
    } finally { [IO.File]::Delete($temporary) }
}
function Stop-AndroidOwnedSupervisorHandle($Process) {
    if ($Process -and !$Process.HasExited) {
        try { $Process.Kill() } catch { if (!$Process.WaitForExit(1000)) { throw } }
        if (!$Process.WaitForExit(5000)) { throw 'Owned supervisor did not stop' }
    }
}
function Save-AndroidOwnedSupervisorLogs($Control) {
    foreach ($entry in @(@('OutputTask','stdout'),@('ErrorTask','stderr'))) {
        $task=$Control.($entry[0])
        if ($task) {
            if (!$task.Wait(2000)) { throw 'Owned supervisor output did not close' }
            [IO.File]::WriteAllText((Join-Path $Control.Directory ('emulator-supervisor.'+$entry[1])),
                $task.GetAwaiter().GetResult(),[Text.UTF8Encoding]::new($false))
        }
    }
}
function Start-AndroidOwnedProcess {
    param([Parameter(Mandatory)][string]$Program,[AllowEmptyCollection()][string[]]$Arguments=@(),
          [Parameter(Mandatory)][string]$Directory,[string]$WorkingDirectory=(Get-Location).Path,
          [ValidateRange(100,30000)][int]$StartupTimeoutMilliseconds=10000,
          [IO.FileStream]$ArtifactLease,[string]$ArtifactRoot,$AdbEndpoint)
    if (!$IsWindows) { throw 'Owned Android host processes require Windows 10 or newer' }
    $directoryKey=Get-AndroidOwnedProcessKey $Directory
    if (!(Test-Path -LiteralPath $directoryKey -PathType Container)) { throw 'Create a fresh run directory before starting its owned process' }
    foreach ($name in @('host-process-request.json','host-process-owner.json','host-process-exit.json',
            'host-process-stop.json','host-process-failed.json','emulator.stdout','emulator.stderr')) {
        if (Test-Path -LiteralPath (Join-Path $directoryKey $name)) { throw 'Use a fresh owned-process attempt directory' }
    }
    Initialize-AndroidOwnedProcessRegistry
    $programPath=(Get-Item -LiteralPath $Program).FullName
    $parent=[Diagnostics.Process]::GetCurrentProcess()
    try { $parentCreation=$parent.StartTime.ToUniversalTime().ToFileTimeUtc().ToString() }
    finally { $parent.Dispose() }
    $request=@{schema_version=1;run_id=[guid]::NewGuid().ToString('N');owner_pid=$PID;
        owner_creation_filetime=$parentCreation;program=$programPath;
        program_sha256=(Get-FileHash -LiteralPath $programPath -Algorithm SHA256).Hash.ToLowerInvariant();
        arguments=@($Arguments);cwd=[IO.Path]::GetFullPath($WorkingDirectory);stdout='emulator.stdout';stderr='emulator.stderr'}
    if ($AdbEndpoint) {
        Assert-AndroidAdbEndpoint $AdbEndpoint
        $request.adb_endpoint=@{schema_version=1;host='localhost';port=[int]$AdbEndpoint.port;socket=[string]$AdbEndpoint.socket}
    }
    if ($ArtifactLease) {
        $artifactKey=Get-AndroidOwnedProcessKey $ArtifactRoot
        if (!$ArtifactLease.CanRead -or (Get-AndroidOwnedProcessKey $ArtifactLease.Name) -ine (Join-Path $artifactKey '.longreach-artifacts.lock')) { throw 'Artifact handle does not belong to this root' }
        $request.artifact_lease=@{root=$artifactKey;handle=$ArtifactLease.SafeFileHandle.DangerousGetHandle().ToInt64().ToString()}
    } elseif ($ArtifactRoot) { throw 'Artifact root requires its held lease' }
    $requestPath=Join-Path $directoryKey 'host-process-request.json'
    $stream=[IO.File]::Open($requestPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { $bytes=[Text.Encoding]::UTF8.GetBytes(($request | ConvertTo-Json -Depth 6));$stream.Write($bytes,0,$bytes.Length) }
    finally { $stream.Dispose() }
    $requestSha=(Get-FileHash -LiteralPath $requestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $python=(Get-Command python -CommandType Application | Select-Object -First 1).Source
    $info=[Diagnostics.ProcessStartInfo]::new($python)
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    foreach ($argument in @("$PSScriptRoot/android-owned-process.py",'supervise','--directory',$directoryKey,'--request-sha256',$requestSha)) { $info.ArgumentList.Add($argument) }
    $process=$null;$control=$null
    try {
        $process=[Diagnostics.Process]::Start($info)
        $creation=$process.StartTime.ToUniversalTime().ToFileTimeUtc().ToString()
        $control=[pscustomobject]@{Directory=$directoryKey;Process=$process;Request=$request;RequestSha=$requestSha;
            Owner=$null;OwnerSha=$null;ArtifactRoot=$ArtifactRoot;OutputTask=$process.StandardOutput.ReadToEndAsync();ErrorTask=$process.StandardError.ReadToEndAsync()}
        $global:LongreachOwnedProcesses[$directoryKey]=$control
        $timer=[Diagnostics.Stopwatch]::StartNew()
        $ownerPath=Join-Path $directoryKey 'host-process-owner.json'
        while (!(Test-Path -LiteralPath $ownerPath)) {
            if ($process.HasExited -or $timer.ElapsedMilliseconds -ge $StartupTimeoutMilliseconds) {
                $failurePath=Join-Path $directoryKey 'host-process-failed.json'
                $detail=if (Test-Path -LiteralPath $failurePath) { (Get-Content -LiteralPath $failurePath -Raw | ConvertFrom-Json).error } else { 'startup deadline or supervisor exit' }
                throw "Could not own host process before startup: $detail"
            }
            Start-Sleep -Milliseconds 20
        }
        $ownerSha=(Get-FileHash -LiteralPath $ownerPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $owner=Get-Content -LiteralPath $ownerPath -Raw | ConvertFrom-Json
        if ($owner.schema_version -ne 1 -or $owner.backend -cne 'windows-job-startup-v2' -or
                $owner.run_id -cne $request.run_id -or $owner.request_sha256 -cne $requestSha -or
                $owner.supervisor_pid -ne $process.Id -or $owner.supervisor_creation_filetime -cne $creation -or
                !$owner.contained_before_start -or $owner.frontend_pid -le 0 -or
                $owner.host_slot -cne 'Global\OpenKaryon.LongreachQt.AndroidEmulatorSlot.v1' -or !$owner.host_slot_acquired_before_start -or
                (Get-FileHash -LiteralPath $requestPath).Hash.ToLowerInvariant() -cne $requestSha -or
                (Get-FileHash -LiteralPath $ownerPath).Hash.ToLowerInvariant() -cne $ownerSha) { throw 'Owned supervisor handshake differs from this launch' }
        if ($ArtifactLease -and (!$owner.artifact_lease_held -or $owner.artifact_lease_root -ine $artifactKey)) { throw 'Supervisor did not retain the artifact lease' }
        if ($AdbEndpoint) {
            if (!$owner.adb_endpoint_applied_before_start) { throw 'Supervisor did not apply the frozen ADB endpoint' }
            Set-AndroidAdbEndpointContext -Directory $directoryKey -Endpoint $request.adb_endpoint -RequestSha $requestSha
        }
        $control.Owner=$owner;$control.OwnerSha=$ownerSha
        $owner.frontend_pid | Set-Content -LiteralPath (Join-Path $directoryKey 'emulator.pid')
        $process.Id | Set-Content -LiteralPath (Join-Path $directoryKey 'emulator-supervisor.pid')
        return $control
    } catch {
        $failure=$_
        if ($AdbEndpoint) { Clear-AndroidAdbEndpointContext $directoryKey -RequestSha $requestSha }
        try { Stop-AndroidOwnedSupervisorHandle $process; if ($control) { Save-AndroidOwnedSupervisorLogs $control } }
        finally { if ($process) { $process.Dispose() };$null=$global:LongreachOwnedProcesses.Remove($directoryKey) }
        throw $failure
    }
}
function Start-AndroidOwnedLogCapture([string]$Directory,[string]$Adb,[string]$Serial,[string]$RemoteFile) {
    $control=Get-AndroidOwnedProcess $Directory
    if(!$control.Process -or $control.Process.HasExited){throw 'Owned emulator must be running before log capture'}
    $requestPath=Join-Path $Directory 'host-logcat-request.json'
    $ownerPath=Join-Path $Directory 'host-logcat-owner.json'
    if((Test-Path -LiteralPath $requestPath) -or (Test-Path -LiteralPath $ownerPath)){throw 'Owned log capture already exists'}
    $program=(Get-Item -LiteralPath $Adb).FullName
    $request=@{schema_version=1;run_id=$control.Request.run_id;request_sha256=$control.RequestSha;
        program=$program;program_sha256=(Get-FileHash -LiteralPath $program).Hash.ToLowerInvariant();
        serial=$Serial;remote_file=$RemoteFile;
        arguments=@(Get-AndroidAdbArguments -Arguments @('-s',$Serial,'shell','logcat','-v','brief','-f',$RemoteFile) -Directory $Directory)}
    Write-AndroidOwnedProcessJson $requestPath $request
    $sha=(Get-FileHash -LiteralPath $requestPath).Hash.ToLowerInvariant()
    $timer=[Diagnostics.Stopwatch]::StartNew()
    while(!(Test-Path -LiteralPath $ownerPath)) {
        if($control.Process.HasExited -or $timer.ElapsedMilliseconds -ge 10000){throw 'Owned log capture startup failed'}
        Start-Sleep -Milliseconds 20
    }
    $owner=Get-Content -LiteralPath $ownerPath -Raw | ConvertFrom-Json
    if($owner.capture_request_sha256 -cne $sha -or $owner.request_sha256 -cne $control.RequestSha -or
        $owner.run_id -cne $control.Request.run_id -or !$owner.contained_before_start -or $owner.client_pid -le 0){throw 'Log capture ownership handshake changed'}
    return @{log_capture_request_sha256=$sha;log_capture_owner_sha256=(Get-FileHash -LiteralPath $ownerPath).Hash.ToLowerInvariant()}
}

function Get-AndroidOwnedProcess([string]$Directory) {
    $directoryKey=Get-AndroidOwnedProcessKey $Directory
    Initialize-AndroidOwnedProcessRegistry
    if ($global:LongreachOwnedProcesses.ContainsKey($directoryKey)) { return $global:LongreachOwnedProcesses[$directoryKey] }
    $requestPath=Join-Path $directoryKey 'host-process-request.json'
    $ownerPath=Join-Path $directoryKey 'host-process-owner.json'
    $requestSha=(Get-FileHash -LiteralPath $requestPath).Hash.ToLowerInvariant()
    $ownerSha=(Get-FileHash -LiteralPath $ownerPath).Hash.ToLowerInvariant()
    $request=Get-Content -LiteralPath $requestPath -Raw | ConvertFrom-Json
    $owner=Get-Content -LiteralPath $ownerPath -Raw | ConvertFrom-Json
    if ($owner.run_id -cne $request.run_id -or $owner.request_sha256 -cne $requestSha -or !$owner.contained_before_start) { throw 'Owned supervisor record differs from this run' }
    $process=$null
    if (!(Test-Path -LiteralPath (Join-Path $directoryKey 'host-process-exit.json'))) {
        try { $process=[Diagnostics.Process]::GetProcessById([int]$owner.supervisor_pid) }
        catch [ArgumentException] { throw 'Owned supervisor disappeared without a completed tree receipt' }
        try {
            $null=$process.Handle
            if ($process.StartTime.ToUniversalTime().ToFileTimeUtc().ToString() -cne $owner.supervisor_creation_filetime) { throw 'Refusing cleanup of a reused supervisor PID' }
        } catch { $process.Dispose();throw }
    }
    $control=[pscustomobject]@{Directory=$directoryKey;Process=$process;Request=$request;RequestSha=$requestSha;
        Owner=$owner;OwnerSha=$ownerSha;ArtifactRoot=$request.artifact_lease.root;OutputTask=$null;ErrorTask=$null}
    $global:LongreachOwnedProcesses[$directoryKey]=$control
    return $control
}
function Stop-AndroidOwnedProcess {
    param([Parameter(Mandatory)]$Control,[ValidateRange(0,7000)][int]$GraceMilliseconds=7000)
    $directoryKey=$Control.Directory
    try {
        foreach ($entry in @(@('host-process-request.json',$Control.RequestSha),@('host-process-owner.json',$Control.OwnerSha))) {
            if ((Get-FileHash -LiteralPath (Join-Path $directoryKey $entry[0])).Hash.ToLowerInvariant() -cne $entry[1]) { throw 'Owned-process launch records changed' }
        }
        if ($Control.Process -and !$Control.Process.HasExited) {
            Write-AndroidOwnedProcessJson (Join-Path $directoryKey 'host-process-stop.json') @{
                run_id=$Control.Request.run_id;request_sha256=$Control.RequestSha;grace_ms=$GraceMilliseconds}
            if (!$Control.Process.WaitForExit($GraceMilliseconds+25000)) { throw 'Owned process tree shutdown timed out' }
        }
        if ($Control.Process -and $Control.Process.ExitCode -ne 0) { throw "Owned supervisor failed with exit code $($Control.Process.ExitCode); see its logs and failure receipt" }
        $python=(Get-Command python -CommandType Application | Select-Object -First 1).Source
        $json=@(& $python "$PSScriptRoot/android-owned-process.py" verify --directory $directoryKey 2>&1)
        if ($LASTEXITCODE) { throw ('Owned process tree validation failed: '+($json -join "`n")) }
        return ($json -join "`n" | ConvertFrom-Json)
    } finally {
        try { Stop-AndroidOwnedSupervisorHandle $Control.Process;Save-AndroidOwnedSupervisorLogs $Control }
        finally {
            if ($Control.Process) { $Control.Process.Dispose();$Control.Process=$null }
            Initialize-AndroidOwnedProcessRegistry
            Clear-AndroidAdbEndpointContext $directoryKey -RequestSha $Control.RequestSha
            $null=$global:LongreachOwnedProcesses.Remove($directoryKey)
        }
    }
}
