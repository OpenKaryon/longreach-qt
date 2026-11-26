# SPDX-License-Identifier: GPL-3.0-or-later
. "$PSScriptRoot/android-adb.ps1"

function Wait-AndroidBoot {
    param(
        [Parameter(Mandatory)][string]$Adb,
        [string]$Serial='emulator-5582',
        [Parameter(Mandatory)][string]$RunDirectory,
        [Parameter(Mandatory)][int]$EmulatorPid,
        [Diagnostics.Process]$EmulatorProcess,
        [ValidateRange(1,600)][int]$TimeoutSeconds=300,
        [ValidateRange(100,10000)][int]$QueryTimeoutMilliseconds=5000,
        [ValidateRange(1,5000)][int]$PollMilliseconds=2000
    )
    $run=(Resolve-Path -LiteralPath $RunDirectory).Path
    $stdout=Join-Path $run 'boot-query.stdout'
    $stderr=Join-Path $run 'boot-query.stderr'
    $ready=Join-Path $run 'boot-ready.json'
    Remove-Item -LiteralPath $ready -Force -ErrorAction SilentlyContinue
    $timer=[Diagnostics.Stopwatch]::StartNew()
    $attempt=0
    $timeouts=0
    function Assert-BootGuest {
        if ($EmulatorProcess) {
            if ($EmulatorProcess.HasExited) { throw 'Owned emulator tree exited during startup; see emulator.stdout' }
        } else {
            $owner=Get-Process -Id $EmulatorPid -ErrorAction SilentlyContinue
            if(!$owner){throw 'Emulator exited during startup; see emulator.stdout'}
            $owner.Dispose()
        }
        foreach($name in @('kernel-shell.log','emulator.stdout')) {
            $path=Join-Path $run $name
            if((Test-Path -LiteralPath $path) -and
                    (Select-String -LiteralPath $path -Pattern 'Kernel panic - not syncing' -Quiet)) {
                throw "Guest kernel panic during startup; see $name"
            }
        }
    }
    while($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        Assert-BootGuest
        Assert-AndroidPinnedAdb $Adb
        $attempt++
        $query=$null
        try {
            $query=Start-Process -FilePath $Adb -ArgumentList @(Get-AndroidAdbArguments -Arguments @('-s',$Serial,'shell','getprop','sys.boot_completed') -Directory $run) -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
            if(!$query.WaitForExit($QueryTimeoutMilliseconds)) {
                $timeouts++
                Stop-Process -InputObject $query -ErrorAction SilentlyContinue
                if(!$query.WaitForExit(1000)){throw 'The owned boot query did not stop'}
            } elseif($query.ExitCode -eq 0 -and
                    (Get-Content -LiteralPath $stdout -Raw) -match '^\s*1\s*$') {
                Assert-BootGuest
                @{attempts=$attempt;query_timeouts=$timeouts;elapsed_ms=$timer.ElapsedMilliseconds} | ConvertTo-Json | Set-Content -LiteralPath $ready
                return
            }
        } finally {
            if($query) {
                if(!$query.HasExited) {
                    Stop-Process -InputObject $query -ErrorAction SilentlyContinue
                    if(!$query.WaitForExit(1000)){throw 'The owned boot query did not stop'}
                }
                $query.Dispose()
            }
        }
        Assert-BootGuest
        Start-Sleep -Milliseconds $PollMilliseconds
    }
    throw "Android did not boot within $TimeoutSeconds seconds ($timeouts timed-out queries)"
}


function Set-AndroidGuestStayAwake {
    param([Parameter(Mandatory)][string]$Adb, [Parameter(Mandatory)][string]$Serial,
          [Parameter(Mandatory)][string]$RunDirectory)
    Invoke-AndroidAdb -Adb $Adb -Arguments @('-s',$Serial,'shell','svc','power','stayon','true') | Out-Null
    $state=@(Invoke-AndroidAdb -Adb $Adb -Arguments @('-s',$Serial,'shell','dumpsys','power'))
    $state | Set-Content -LiteralPath (Join-Path $RunDirectory 'power-before.txt')
    if (($state -join "`n") -notmatch '\bmStayOn(?:Conditions|Setting)=(?:3|7)\b') {
        throw 'The guest did not confirm stay-awake on all power sources'
    }
}
