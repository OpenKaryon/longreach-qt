# SPDX-License-Identifier: GPL-3.0-or-later
# Legacy adb shell can return host success after a remote command fails.
function Invoke-AndroidSetupCommand {
    param([Parameter(Mandatory)][string]$Adb,[Parameter(Mandatory)][string]$Serial,
          [Parameter(Mandatory)][ValidatePattern('^[a-z0-9-]+$')][string]$Step,
          [Parameter(Mandatory)][string]$Command,[Parameter(Mandatory)][string]$OutputPath)
    $marker='LONGREACH_SHELL_'+[guid]::NewGuid().ToString('N')
    # Commands are runner-owned shell fragments. A subshell also captures an
    # explicit exit without preventing the outer shell from printing status.
    $wrapped='( '+$Command+' ); longreach_status=$?; printf ''\n'+$marker+':%s\n'' "$longreach_status"; exit "$longreach_status"'
    # A transport failure must not leave an earlier successful setup transcript.
    [IO.File]::WriteAllText($OutputPath,'',[Text.UTF8Encoding]::new($false))
    $lines=@(Invoke-AndroidApi21Adb -Adb $Adb -Serial $Serial -Parameters @('shell',$wrapped) -TimeoutMilliseconds 15000)
    $clientCode=$LASTEXITCODE
    [IO.File]::WriteAllLines($OutputPath,[string[]]$lines,[Text.UTF8Encoding]::new($false))
    if ($clientCode -ne 0) { throw "Android setup $Step ADB client failed with status $clientCode" }
    $status=@($lines | Where-Object { ([string]$_).StartsWith($marker+':',[StringComparison]::Ordinal) })
    if ($status.Count -ne 1 -or $status[0] -cnotmatch ('^'+$marker+':(0|[1-9][0-9]{0,2})$')) {
        throw "Missing or invalid Android setup status marker: $Step"
    }
    $code=[int]$Matches[1]
    if ($code -gt 255) { throw "Missing or invalid Android setup status marker: $Step" }
    if ($code -ne 0) { throw "Remote Android setup $Step failed with status $code" }
    return @($lines | Where-Object { !([string]$_).StartsWith($marker+':',[StringComparison]::Ordinal) })
}
