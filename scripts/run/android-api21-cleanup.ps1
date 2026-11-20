# SPDX-License-Identifier: GPL-3.0-or-later
param([Parameter(Mandatory)][string]$Adb, [string]$Serial='emulator-5582',
      [Parameter(Mandatory)][string]$RunDirectory, [Parameter(Mandatory)][int]$EmulatorPid)
$ErrorActionPreference='Stop'
$runPath = ([IO.Path]::GetFullPath($RunDirectory)).Replace('/','\')
$children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$EmulatorPid" |
    Where-Object { $_.CommandLine -and $_.CommandLine.Replace('/','\').Contains($runPath, [StringComparison]::OrdinalIgnoreCase) })
function Stop-OwnedChildren {
    foreach ($child in $children) {
        $current = Get-CimInstance Win32_Process -Filter "ProcessId=$($child.ProcessId)"
        if ($current -and $current.ParentProcessId -eq $EmulatorPid -and $current.CommandLine -and
                $current.CommandLine.Replace('/','\').Contains($runPath, [StringComparison]::OrdinalIgnoreCase)) {
            $ownedChild = Get-Process -Id $child.ProcessId -ErrorAction SilentlyContinue
            if ($ownedChild) {
                Stop-Process -InputObject $ownedChild -ErrorAction SilentlyContinue
                if (!$ownedChild.WaitForExit(7000)) { throw 'Task-owned QEMU child did not stop.' }
            }
        }
    }
}
$owner = Get-CimInstance Win32_Process -Filter "ProcessId=$EmulatorPid"
if ($owner -and (!$owner.CommandLine -or
        !$owner.CommandLine.Replace('/','\').Contains($runPath, [StringComparison]::OrdinalIgnoreCase))) {
    throw 'Refusing cleanup: emulator PID no longer belongs to this run.'
}
$owned=Get-Process -Id $EmulatorPid -ErrorAction SilentlyContinue
if (!$owned) {
    Stop-OwnedChildren
    'Emulator exited before final log capture.' | Set-Content "$RunDirectory/final-logcat.log"
    return
}
foreach ($request in @(
    @{Arguments=@('-s',$Serial,'logcat','-d','-v','brief');Name='final-logcat'},
    @{Arguments=@('-s',$Serial,'emu','kill');Name='emulator-stop'})) {
    $client=Start-Process -FilePath $Adb -ArgumentList $request.Arguments -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput "$RunDirectory/$($request.Name).log" -RedirectStandardError "$RunDirectory/$($request.Name).stderr"
    if (!$client.WaitForExit(5000)) {
        Stop-Process -Id $client.Id -ErrorAction SilentlyContinue
        $client.WaitForExit()
        "Timed out waiting for $($request.Name)." | Add-Content "$RunDirectory/cleanup.log"
    }
}
if (!$owned.WaitForExit(7000)) {
    Stop-OwnedChildren
    Stop-Process -Id $owned.Id -ErrorAction SilentlyContinue
    $owned.WaitForExit()
    'Stopped the task-owned emulator after console shutdown timed out.' | Add-Content "$RunDirectory/cleanup.log"
}
# The frontend can exit normally while its identified QEMU child remains.
Stop-OwnedChildren
