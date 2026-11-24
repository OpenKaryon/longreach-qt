# SPDX-License-Identifier: GPL-3.0-or-later
# adb shell joins its argv into a remote shell command. Preserve an am string
# extra as one value even when the application receives several flags.
function ConvertTo-AndroidShellArgument {
    param([AllowEmptyString()][string]$Value)
    if ($Value -cmatch '^[A-Za-z0-9_./:=+-]+$') { return $Value }
    $quote=[string][char]39
    $escapedQuote=$quote + [char]34 + $quote + [char]34 + $quote
    return $quote + $Value.Replace($quote,$escapedQuote) + $quote
}

function Assert-AndroidActivityLaunch {
    param([string[]]$Output,[string]$Component)
    $starts=@($Output | Where-Object { $_ -match '^Starting: Intent \{' })
    if ($starts.Count -ne 1 -or !$starts[0].Contains("cmp=$Component ") -or
            $Output -match '^Error:|java\.lang\..*Exception|^Starting: null') {
        throw 'Android am did not accept the requested activity; see launch.txt'
    }
}
