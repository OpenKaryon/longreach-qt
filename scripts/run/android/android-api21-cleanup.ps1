# SPDX-License-Identifier: GPL-3.0-or-later
param([Parameter(Mandatory)][string]$Adb,[string]$Serial='emulator-5582',
      [Parameter(Mandatory)][string]$RunDirectory,[int]$EmulatorPid,
      [ValidateRange(0,7000)][int]$GraceMilliseconds=7000,[switch]$RequireFinalLog)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/android-owned-process.ps1"
. "$PSScriptRoot/android-process-exit.ps1"
$owner=Get-AndroidOwnedProcess $RunDirectory
if ($EmulatorPid -and $EmulatorPid -ne $owner.Owner.frontend_pid) { throw 'Refusing cleanup: frontend PID belongs to a different owned run' }
$finalCaptured=$false
try {
    if ($owner.Process -and !$owner.Process.HasExited) {
        try {
            $lines=@(Invoke-AndroidExitQuery -Adb $Adb -Serial $Serial -Command @('logcat','-d','-v','brief') -Directory $RunDirectory -Name 'final-logcat' -TimeoutMilliseconds 5000 -AllowNonzero:(!$RequireFinalLog))
            if ($RequireFinalLog -and !$lines.Count) { throw 'Required final Android log capture is empty' }
            $lines | Set-Content -LiteralPath "$RunDirectory/final-logcat.log"
            if ($RequireFinalLog) {
                Write-AndroidOwnedProcessJson "$RunDirectory/final-logcat-capture.json" @{
                    schema_version=1;serial=$Serial;captured=$true;
                    host_process_owner_sha256=$owner.OwnerSha;host_process_request_sha256=$owner.RequestSha;
                    logcat_sha256=(Get-FileHash "$RunDirectory/final-logcat.log").Hash.ToLowerInvariant()}
                $finalCaptured=$true
            }
        } catch { $_.Exception.Message | Add-Content -LiteralPath "$RunDirectory/cleanup.log" }
    } else { 'Owned tree exited before final log capture.' | Set-Content -LiteralPath "$RunDirectory/final-logcat.log" }
} finally { $proof=Stop-AndroidOwnedProcess $owner -GraceMilliseconds $GraceMilliseconds }
if ($RequireFinalLog -and !$finalCaptured) { throw 'Required final Android log capture failed; owned tree was stopped' }
$proof
