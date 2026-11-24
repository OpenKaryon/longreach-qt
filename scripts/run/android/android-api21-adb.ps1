# SPDX-License-Identifier: GPL-3.0-or-later
# API21 suite boundary retained for recording fixtures.
. "$PSScriptRoot/android-adb.ps1"
function Invoke-AndroidApi21Adb {
    param([string]$Adb,[string]$Serial,[string[]]$Parameters,[switch]$AllowNonzero,
          [ValidateRange(0,600000)][int]$TimeoutMilliseconds=0)
    $arguments=if ($Serial) { @('-s',$Serial)+$Parameters } else { $Parameters }
    Invoke-AndroidAdb -Adb $Adb -Arguments $arguments -AllowNonzero:$AllowNonzero -TimeoutMilliseconds $TimeoutMilliseconds
}
