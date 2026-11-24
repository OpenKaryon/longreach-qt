# SPDX-License-Identifier: GPL-3.0-or-later
# Ordinary am string-extra round trips; no Android/device commands.
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../run/android-shell.ps1"
$cases=@('--selftest','--qt-checks-only --android-crash-hold','--label "hello world"',"--label 'hello world'",'')
$records=@($cases | ForEach-Object { @{value=$_;encoded=(ConvertTo-AndroidShellArgument $_)} })
$temporary=[IO.Path]::GetTempFileName()
try {
    $records | ConvertTo-Json | Set-Content -LiteralPath $temporary -Encoding utf8
    & python -c 'import json,shlex,sys; rows=json.load(open(sys.argv[1],encoding="utf-8-sig")); assert len(rows)==5; assert all(shlex.split("am start --es applicationArguments "+row["encoded"]) == ["am","start","--es","applicationArguments",row["value"]] for row in rows); print("5 Android am string-extra round trips PASS")' $temporary
    if ($LASTEXITCODE) { throw 'Remote shell argument round trip failed' }
} finally { [IO.File]::Delete($temporary) }

$component='org.longreachqt.examples.qtselftest/org.longreachqt.examples.SmokeActivity'
Assert-AndroidActivityLaunch -Output @("Starting: Intent { cmp=$component (has extras) }") -Component $component
foreach ($rejected in @(@('Starting: null','java.lang.NullPointerException'),@('usage: am start'),@('Starting: Intent { cmp=org.example/Other }'))) {
    try {
        Assert-AndroidActivityLaunch -Output $rejected -Component $component
        throw 'Invalid activity launch was accepted'
    } catch {
        if ($_.Exception.Message -cne 'Android am did not accept the requested activity; see launch.txt') { throw }
    }
}
'Android activity launch: valid receipt and 3 rejected launch reports PASS'
