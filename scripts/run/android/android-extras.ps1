# SPDX-License-Identifier: GPL-3.0-or-later
# Observe these two bound QtService processes independently of client assertions.
function Observe-AndroidExtrasServices {
    param([string]$Adb,[string]$Serial,[string]$Directory,[string]$Package,[string]$Marker)
    if (Test-Path -LiteralPath "$Directory/extras-services.json") { return }
    $state="$PSScriptRoot/android-extras-state.py"
    # Functions are dot-sourced; resolve this file's sibling from its saved path.
    if ($script:AndroidExtrasStateScript) { $state=$script:AndroidExtrasStateScript }
    if ($Package -cnotmatch '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$') { throw 'Invalid AndroidExtras package' }
    foreach ($round in 0,1) {
        $stem="extras-$round"
        $live="$Directory/$stem-live.json";$exit="$Directory/$stem-exit.json"
        if (Test-Path -LiteralPath $exit) { continue }
        if (!(Test-Path -LiteralPath $live)) {
            $lines=@(Invoke-AndroidExitQuery -Adb $Adb -Serial $Serial -Directory $Directory -Name "$stem-live-request" `
                -Command @('shell','cat',"/data/data/$Package/files/extras-service-$round-live.txt") -AllowNonzero)
            if (!$lines.Count) { return }
            # Gingerbread shell reports ENOENT on stdout and has no test/[ builtin.
            # Only this exact pending path is optional; other output remains an error.
            if (($lines -join "`n").Trim() -ceq "/data/data/$Package/files/extras-service-$round-live.txt`: No such file or directory") { return }
            $request=($lines -join "`n").Trim()
            if ($request -cnotmatch '^([1-9][0-9]*) ([0-9a-f]{32})$') { throw 'Invalid service live rendezvous' }
            $serviceNumber=[int]$Matches[1]
            if ($round -eq 1) {
                if (!(Test-Path -LiteralPath "$Directory/extras-round1-marker.txt")) { throw 'Service restarted before its host launch boundary' }
                $Marker=(Get-Content -LiteralPath "$Directory/extras-round1-marker.txt" -Raw).Trim()
            }
            Invoke-AndroidExitQuery -Adb $Adb -Serial $Serial -Directory $Directory -Name "$stem-live-stat-a" `
                -Command @('shell','cat',"/proc/$serviceNumber/stat") | Out-Null
            Invoke-AndroidExitQuery -Adb $Adb -Serial $Serial -Directory $Directory -Name "$stem-live-cmdline" `
                -Command @('shell','cat',"/proc/$serviceNumber/cmdline") | Out-Null
            Invoke-AndroidExitQuery -Adb $Adb -Serial $Serial -Directory $Directory -Name "$stem-live-stat-b" `
                -Command @('shell','cat',"/proc/$serviceNumber/stat") | Out-Null
            & python $state observe --case $Directory --package $Package --round $round --marker $Marker
            if ($LASTEXITCODE) { throw 'Live service identity was not confirmed' }
            Invoke-AndroidExitQuery -Adb $Adb -Serial $Serial -Directory $Directory -Name "$stem-live-ack-push" `
                -Command @('push',"$Directory/extras-service-$round-live-ack.txt","/data/data/$Package/files/extras-service-$round-live-ack.txt") | Out-Null
            return
        }
        $lines=@(Invoke-AndroidExitQuery -Adb $Adb -Serial $Serial -Directory $Directory -Name "$stem-exit-request" `
            -Command @('shell','cat',"/data/data/$Package/files/extras-service-$round-exit.txt") -AllowNonzero)
        if (!$lines.Count) { return }
        # Gingerbread shell reports ENOENT on stdout and has no test/[ builtin.
        # Only this exact pending path is optional; other output remains an error.
        if (($lines -join "`n").Trim() -ceq "/data/data/$Package/files/extras-service-$round-exit.txt`: No such file or directory") { return }
        $observed=Get-Content -LiteralPath $live -Raw | ConvertFrom-Json
        $timer=[Diagnostics.Stopwatch]::StartNew();$sample=0
        while ($sample -lt 2) {
            if ($timer.ElapsedMilliseconds -ge 20000) { throw 'Host did not observe the service exit in time' }
            $logName="$stem-exit-log-$sample"
            $raw=@(Get-AndroidCaseRawLog -Adb $Adb -Serial $Serial -Directory $Directory -Name $logName -TimeoutMilliseconds 5000)
            $ps=@(Invoke-AndroidExitQuery -Adb $Adb -Serial $Serial -Directory $Directory -Name "$stem-exit-ps-$sample" -Command @('shell','ps'))
            $scoped=@(Get-AndroidApi21CaseLog -RawLog $raw -Marker $observed.log_marker)
            $lifecycle=Get-AndroidApplicationLifecycle $scoped $observed.package
            if ($lifecycle -and $lifecycle.death_line -and $lifecycle.process_id -eq $observed.pid -and
                    !(Test-AndroidApplicationPresent $ps $observed.package $observed.pid)) { $sample++ }
            Start-Sleep -Milliseconds 100
        }
        & python $state exit --case $Directory --package $Package --round $round
        if ($LASTEXITCODE) { throw 'Service host exit evidence is incomplete' }
        if ($round -eq 0) {
            $next='BEGIN-'+[guid]::NewGuid().ToString('N')
            $next | Set-Content -LiteralPath "$Directory/extras-round1-marker.txt" -Encoding utf8
            Invoke-AndroidExitQuery -Adb $Adb -Serial $Serial -Directory $Directory -Name 'extras-round1-marker' `
                -Command @('shell','log','-p','i','-t','LongreachCase',$next) | Out-Null
        } else {
            & python $state seal --case $Directory --package $Package
            if ($LASTEXITCODE) { throw 'Two service host exits were not sealed' }
        }
        Invoke-AndroidExitQuery -Adb $Adb -Serial $Serial -Directory $Directory -Name "$stem-exit-ack-push" `
            -Command @('push',"$Directory/extras-service-$round-exit-ack.txt","/data/data/$Package/files/extras-service-$round-exit-ack.txt") | Out-Null
        return
    }
}
$script:AndroidExtrasStateScript=Join-Path $PSScriptRoot 'android-extras-state.py'
