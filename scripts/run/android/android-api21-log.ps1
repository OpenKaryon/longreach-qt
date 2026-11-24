# SPDX-License-Identifier: GPL-3.0-or-later

# API21 logd can retain records across -c. Scope every check to a unique
# marker written after install/reset and before this application launch.
function Get-AndroidApi21CaseLog {
    param([Parameter(Mandatory)][AllowEmptyCollection()][AllowEmptyString()][string[]]$RawLog,
          [Parameter(Mandatory)][string]$Marker)
    if ($Marker -notmatch '^BEGIN-[0-9a-f]{32}$') { throw 'Invalid Android case log marker' }
    $pattern = '^[VDIWEF]/LongreachCase\s*\(\s*\d+\):\s*' + [regex]::Escape($Marker) + '\s*$'
    $indices = @(for ($index = 0; $index -lt $RawLog.Count; $index++) {
        if ($RawLog[$index] -match $pattern) { $index }
    })
    if ($indices.Count -ne 1) { throw 'Expected exactly one current Android case log marker' }
    $RawLog | Select-Object -Skip ($indices[0] + 1)
}
