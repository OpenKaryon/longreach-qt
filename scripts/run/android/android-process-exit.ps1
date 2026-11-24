# SPDX-License-Identifier: GPL-3.0-or-later
. "$PSScriptRoot/android-adb-endpoint.ps1"
# Copyright (C) 2026 OpenKaryon
# A native result file precedes Qt global teardown. Require observed process exit.
. "$PSScriptRoot/android-api21-log.ps1"

function Get-AndroidApplicationLifecycle([string[]]$Log,[string]$Package) {
    $pkg=[regex]::Escape($Package)
    $am='^[VDIWEF]/ActivityManager\s*\(\s*\d+\):\s*'
    $starts=@()
    $deaths=@()
    for ($index=0;$index -lt $Log.Count;$index++) {
        $line=$Log[$index]
        if ($line -match 'FATAL EXCEPTION|Fatal signal|exiting due to signal|terminated by signal|VM aborting|\*\*\*\s+\*\*\*\s+\*\*\*' -or
                $line -match ('>>>\s*'+$pkg+'\s*<<<')) { throw "Fatal cleanup error: $line" }
        if ($line -match ($am+'Start proc '+$pkg+'(?:\s+.*)?:\s*pid=(\d+)(?:\s|$)') -or
                $line -match ($am+'Start proc (\d+):'+$pkg+'(?:/|\s|$)')) {
            $starts+=@{pid=[int]$Matches[1];index=$index;line=$line}
        }
        if ($line -match ($am+'Process '+$pkg+' \(pid (\d+)\) has died\b')) {
            $deaths+=@{pid=[int]$Matches[1];index=$index;line=$line}
        }
    }
    if (!$starts.Count) { return $null }
    if ($starts.Count -ne 1 -or $starts[0].pid -le 0) { throw 'Ambiguous application process launch' }
    $start=$starts[0]
    $matching=@($deaths | Where-Object { $_.pid -eq $start.pid -and $_.index -gt $start.index })
    if ($matching.Count -gt 1) { throw 'Ambiguous application process death' }
    $end=if ($matching.Count) { $matching[0].index } else { $Log.Count-1 }
    foreach ($line in @($Log | Select-Object -Skip $start.index -First ($end-$start.index+1))) {
        if ($line -match ($am+'(?:Force stopping(?: package)? '+$pkg+'(?:\s|:|$)|Killing (?:\d+:)?'+$pkg+'(?:/|\s|$))')) {
            throw 'Application was killed or force-stopped during the case'
        }
    }
    return [pscustomobject]@{process_id=$start.pid;start_line=$start.line;
        death_line=$(if ($matching.Count) { $matching[0].line } else { $null })}
}

function Test-AndroidApplicationPresent([string[]]$Ps,[string]$Package,[int]$ProcessId) {
    $lines=@($Ps | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if (!$lines.Count) { throw 'Empty Android ps observation' }
    $header=$lines[0] -split '\s+'
    $pidColumn=[Array]::IndexOf($header,'PID')
    if ($pidColumn -lt 0 -or $header[-1] -notin @('NAME','CMD','COMMAND','ARGS')) { throw 'Unrecognized Android ps header' }
    $rows=0
    foreach ($line in @($lines | Select-Object -Skip 1)) {
        $parts=$line -split '\s+'
        $processNumber=0
        if ($parts.Count -lt $header.Count -or ![int]::TryParse($parts[$pidColumn],[ref]$processNumber) -or $processNumber -le 0) {
            throw 'Unrecognized Android ps row'
        }
        $rows++
        $name=$parts[-1]
        if ($processNumber -eq $ProcessId -or $name -ceq $Package -or $name.StartsWith($Package+':',[StringComparison]::Ordinal)) { return $true }
    }
    if (!$rows) { throw 'Android ps observation contains no processes' }
    return $false
}

function Invoke-AndroidExitQuery {
    param([string]$Adb,[string]$Serial,[string[]]$Command,[string]$Directory,[string]$Name,
          [int]$TimeoutMilliseconds=5000,[switch]$AllowNonzero)
    $stdout=Join-Path $Directory ($Name+'.stdout')
    $stderr=Join-Path $Directory ($Name+'.stderr')
    $query=$null
    try {
        $query=Start-Process -FilePath $Adb -ArgumentList @(Get-AndroidAdbArguments -Arguments (@('-s',$Serial)+$Command) -Directory $Directory) -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        if (!$query.WaitForExit($TimeoutMilliseconds)) { throw "Timed out observing Android process exit: $Name" }
        if ($query.ExitCode -ne 0) {
            if (!$AllowNonzero) { throw "ADB process-exit observation failed: $Name" }
            return # Failed polls cannot turn a stdout zero into completion.
        }
        return @(Get-Content -LiteralPath $stdout)
    } finally {
        if ($query) {
            if (!$query.HasExited) {
                Stop-Process -InputObject $query -ErrorAction SilentlyContinue
                if (!$query.WaitForExit(1000)) { throw 'Owned process-exit query did not stop' }
            }
            $query.Dispose()
        }
    }
}

function Get-AndroidProcessObservation([string]$Adb,[string]$Serial,[string]$Directory,[int]$TimeoutMilliseconds) {
    $timer=[Diagnostics.Stopwatch]::StartNew()
    $raw=@(Get-AndroidCaseRawLog $Adb $Serial $Directory 'process-exit-logcat-query' ([Math]::Min(5000,$TimeoutMilliseconds)))
    $left=$TimeoutMilliseconds-[int]$timer.ElapsedMilliseconds
    if ($left -le 0) { throw 'Process-exit observation deadline elapsed before ps' }
    # The ps snapshot must follow the death log, rather than precede app startup.
    $ps=@(Invoke-AndroidExitQuery $Adb $Serial @('shell','ps') $Directory 'process-exit-ps-query' ([Math]::Min(5000,$left)))
    return [pscustomobject]@{RawLog=$raw;Ps=$ps}
}

# API10's small kernel ring can rotate between launch and the first dump.
# The ADB writer belongs to the emulator's existing Windows job. Readiness
# and fresh fences must reach the guest file before accepting each snapshot.
function Start-AndroidCaseLogCapture([string]$Adb,[string]$Serial,[string]$Directory) {
    $path=Join-Path $Directory 'logcat-capture.json'
    if(Test-Path -LiteralPath $path){throw 'Case log capture already exists'}
    $id=[guid]::NewGuid().ToString('N')
    $remote='/data/local/longreach-log-'+$id+'.log'
    $ready='READY-'+$id
    $owner=Start-AndroidOwnedLogCapture -Directory $Directory -Adb $Adb -Serial $Serial -RemoteFile $remote
    Invoke-AndroidExitQuery $Adb $Serial @('shell','log','-p','i','-t','LongreachCapture',$ready) $Directory 'logcat-capture-ready-marker' 5000 | Out-Null
    $timer=[Diagnostics.Stopwatch]::StartNew()
    do {
        $lines=@(Invoke-AndroidExitQuery $Adb $Serial @('shell','cat',$remote) $Directory 'logcat-capture-ready-query' 1000 -AllowNonzero)
        if(@($lines | Where-Object {$_ -match ('^[VDIWEF]/LongreachCapture\s*\(\s*\d+\):\s*'+$ready+'\s*$')}).Count -eq 1){break}
        if($timer.ElapsedMilliseconds -ge 5000){
            throw 'Guest log capture did not become ready'
        }
        Start-Sleep -Milliseconds 50
    } while($true)
    $lines | Set-Content -LiteralPath "$Directory/logcat-capture-ready.log" -Encoding utf8
    $record=@{schema_version=1;serial=$Serial;remote_file=$remote;ready_marker=$ready;
        log_capture_request_sha256=$owner.log_capture_request_sha256;log_capture_owner_sha256=$owner.log_capture_owner_sha256;
        ready_log_sha256=(Get-FileHash -LiteralPath "$Directory/logcat-capture-ready.log").Hash.ToLowerInvariant()}
    $record | ConvertTo-Json | Set-Content -LiteralPath $path -Encoding utf8
    return (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()
}

function Get-AndroidCaseRawLog([string]$Adb,[string]$Serial,[string]$Directory,[string]$Name,[int]$TimeoutMilliseconds=5000) {
    $path=Join-Path $Directory 'logcat-capture.json'
    $receiptPath=Join-Path $Directory 'input-receipt.json'
    $receipt=if(Test-Path -LiteralPath $receiptPath){Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json}else{$null}
    if(!(Test-Path -LiteralPath $path)) {
        if($receipt.log_capture_sha256){throw 'Bound guest log capture is missing'}
        return @(Invoke-AndroidExitQuery $Adb $Serial @('logcat','-d','-v','brief') $Directory $Name $TimeoutMilliseconds)
    }
    $capture=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if($capture.schema_version -ne 1 -or $capture.serial -cne $Serial -or
        $capture.remote_file -cnotmatch '^/data/local/longreach-log-[0-9a-f]{32}\.log$' -or
        $capture.ready_marker -cne ('READY-'+[IO.Path]::GetFileNameWithoutExtension($capture.remote_file).Substring(14)) -or
        !$receipt.log_capture_sha256 -or $receipt.log_capture_sha256 -cne (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant()) {
        throw 'Guest log capture differs from its case receipt'
    }
    $timer=[Diagnostics.Stopwatch]::StartNew()
    $fence='CAPTURE-'+[guid]::NewGuid().ToString('N')
    Invoke-AndroidExitQuery $Adb $Serial @('shell','log','-p','i','-t','LongreachCapture',$fence) $Directory ($Name+'-fence') $TimeoutMilliseconds | Out-Null
    do {
        $remaining=$TimeoutMilliseconds-[int]$timer.ElapsedMilliseconds
        if($remaining -le 0){throw 'Guest log capture freshness deadline elapsed'}
        $lines=@(Invoke-AndroidExitQuery $Adb $Serial @('shell','cat',$capture.remote_file) $Directory $Name $remaining)
        $pattern='^[VDIWEF]/LongreachCapture\s*\(\s*\d+\):\s*'+$fence+'\s*$'
        if(@($lines | Where-Object {$_ -match $pattern}).Count -eq 1){
            if($timer.ElapsedMilliseconds -ge $TimeoutMilliseconds){throw 'Guest log capture freshness deadline elapsed'}
            @{schema_version=1;serial=$Serial;fence_marker=$fence;log_capture_sha256=$receipt.log_capture_sha256;
                snapshot_sha256=(Get-FileHash -LiteralPath "$Directory/$Name.stdout").Hash.ToLowerInvariant()} |
                ConvertTo-Json | Set-Content -LiteralPath "$Directory/$Name-file-capture.json" -Encoding utf8
            return $lines
        }
        Start-Sleep -Milliseconds ([Math]::Min(25,[Math]::Max(1,$TimeoutMilliseconds-[int]$timer.ElapsedMilliseconds)))
    } while($true)
}

function Wait-AndroidApplicationExit {
    param([string]$Adb,[string]$Serial,[string]$Directory,[string]$Package,[string]$Marker,
          [ValidateRange(1,60)][int]$TimeoutSeconds=60,[ValidateRange(1,1000)][int]$PollMilliseconds=250)
    $proofPath=Join-Path $Directory 'process-exit.json'
    [IO.File]::Delete($proofPath)
    $timer=[Diagnostics.Stopwatch]::StartNew()
    $observations=0
    $absent=0
    while ($timer.ElapsedMilliseconds -lt $TimeoutSeconds*1000) {
        $remaining=$TimeoutSeconds*1000-[int]$timer.ElapsedMilliseconds
        $snapshot=Get-AndroidProcessObservation $Adb $Serial $Directory $remaining
        $observations++
        $snapshot.RawLog | Set-Content -LiteralPath "$Directory/logcat-raw.log" -Encoding utf8
        $snapshot.Ps | Set-Content -LiteralPath "$Directory/process-exit-ps.txt" -Encoding utf8
        $log=@(Get-AndroidApi21CaseLog -RawLog $snapshot.RawLog -Marker $Marker)
        $log | Set-Content -LiteralPath "$Directory/logcat.log" -Encoding utf8
        $lifecycle=Get-AndroidApplicationLifecycle $log $Package
        $processNumber=if ($lifecycle) { $lifecycle.process_id } else { 0 }
        $present=Test-AndroidApplicationPresent $snapshot.Ps $Package $processNumber
        if ($lifecycle -and $lifecycle.death_line -and !$present) { $absent++ } else { $absent=0 }
        if ($absent -ge 2 -and $timer.ElapsedMilliseconds -lt $TimeoutSeconds*1000) {
            $proof=@{schema_version=1;package=$Package;process_id=$lifecycle.process_id;log_marker=$Marker;
                process_exit_confirmed=$true;termination_policy='natural';observation_order='logcat-then-ps';
                start_line=$lifecycle.start_line;death_line=$lifecycle.death_line;observations=$observations;
                elapsed_ms=$timer.ElapsedMilliseconds;timeout_seconds=$TimeoutSeconds;
                logcat_sha256=(Get-FileHash -LiteralPath "$Directory/logcat.log").Hash.ToLowerInvariant();
                raw_logcat_sha256=(Get-FileHash -LiteralPath "$Directory/logcat-raw.log").Hash.ToLowerInvariant();
                ps_sha256=(Get-FileHash -LiteralPath "$Directory/process-exit-ps.txt").Hash.ToLowerInvariant()}
            if(Test-Path -LiteralPath "$Directory/logcat-capture.json") {
                $proof.log_capture_observation_sha256=(Get-FileHash -LiteralPath "$Directory/process-exit-logcat-query-file-capture.json").Hash.ToLowerInvariant()
            }
            $temporary=$proofPath+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
            try {
                $proof | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $temporary -Encoding utf8
                [IO.File]::Move($temporary,$proofPath)
            } finally { [IO.File]::Delete($temporary) }
            return [pscustomobject]$proof
        }
        $remaining=$TimeoutSeconds*1000-[int]$timer.ElapsedMilliseconds
        if ($remaining -gt 0) { Start-Sleep -Milliseconds ([Math]::Min($PollMilliseconds,$remaining)) }
    }
    throw "Application process exit was not confirmed within $TimeoutSeconds seconds: $Package"
}
