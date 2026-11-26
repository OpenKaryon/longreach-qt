# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
<# Execute the real result polling loops with recorded ADB boundaries; no guests. #>
param([string]$RepoRoot=(Resolve-Path "$PSScriptRoot/../../..").Path)
$ErrorActionPreference='Stop'
. "$RepoRoot/scripts/run/android/android-process-exit.ps1"
$parent=(New-Item -ItemType Directory -Force "$RepoRoot/build/fixtures").FullName
$fixture=Join-Path $parent ('android-terminal-result-'+[guid]::NewGuid())
New-Item -ItemType Directory -Path $fixture | Out-Null
$script:TerminalState=$null
function Start-Sleep { param($Seconds) }
function Invoke-AndroidExitQuery {
    param($Adb,$Serial,$Command,$Directory,$Name,$TimeoutMilliseconds,[switch]$AllowNonzero)
    $script:TerminalState.queries.Add(@{name=$Name;timeout=$TimeoutMilliseconds;allow_nonzero=[bool]$AllowNonzero;command=@($Command)})
    if($Name -eq 'native-result-after-death'){
        if($TimeoutMilliseconds -ne 5000 -or !$AllowNonzero){throw 'Terminal read must be bounded and preserve nonzero refusal'}
        if($script:TerminalState.mode -eq 'timeout'){throw 'synthetic terminal query timeout'}
        return @($script:TerminalState.terminal)
    }
    if($script:TerminalState.mode -eq 'immediate'){return @('0')}
    return @('/data/data/org.longreach.fixture/files/selftest-result.txt: No such file or directory')
}
function Invoke-Adb {
    param($Parameters,[switch]$AllowNonzero)
    if($Parameters[0] -eq 'logcat'){return @(Get-TerminalFixtureLog)}
    return @(Invoke-AndroidExitQuery -Name native-result -Command $Parameters -AllowNonzero:$AllowNonzero)
}
function Get-TerminalFixtureLog {
    $lines=@('I/LongreachCase( 427): BEGIN-0123456789abcdef0123456789abcdef',
        'I/ActivityManager( 68): Start proc org.longreach.fixture for activity: pid=437 uid=10001 gids={3003}')
    if($script:TerminalState.mode -eq 'fatal'){$lines+='E/AndroidRuntime( 437): FATAL EXCEPTION: main'}
    if($script:TerminalState.mode -ne 'running'){$lines+='I/ActivityManager( 68): Process org.longreach.fixture (pid 437) has died.'}
    return $lines
}
function Get-AndroidCaseRawLog {
    param($Adb,$Serial,$Directory,$Name,$TimeoutMilliseconds)
    return @(Get-TerminalFixtureLog)
}
function Invoke-AndroidApi21Adb { param($Adb,$Serial,$Parameters,[switch]$AllowNonzero,$TimeoutMilliseconds) }
try {
    foreach($entry in @('qt5-android-gingerbread.ps1','android-api21-suite.ps1')){
        $parseErrors=$null
        $tree=[Management.Automation.Language.Parser]::ParseFile("$RepoRoot/scripts/run/$entry",[ref]$null,[ref]$parseErrors)
        if($parseErrors){throw ($parseErrors|Out-String)}
        $loops=@($tree.FindAll({param($node) $node -is [Management.Automation.Language.ForStatementAst] -and $node.Extent.Text -match '\$attempt = 0; \$attempt -lt (120|300)'},$true))
        $gates=@($tree.FindAll({param($node) $node -is [Management.Automation.Language.IfStatementAst] -and $node.Extent.Text.StartsWith('if (!$complete -or !(')},$true))
        if($loops.Count -ne 1 -or $gates.Count -ne 1){throw "Cannot find actual completion loop/gate: $entry"}
        foreach($mode in @('late-zero','late-nonzero','still-missing','timeout','fatal','running','immediate')){
            $terminal=switch($mode){'late-zero'{@('0')}'late-nonzero'{@('1')}default{@()}}
            $script:TerminalState=@{mode=$mode;terminal=$terminal;queries=[Collections.Generic.List[object]]::new()}
            $adb='recording-adb';$serial='recording-serial';$Package='org.longreach.fixture';$completionName='selftest-result.txt'
            $output=$fixture;$destination=$fixture;$logMarker='BEGIN-0123456789abcdef0123456789abcdef'
            $extrasBehavior=$false;$AndroidExtrasBehavior=$false;$case=@{Name='fixture'}
            $process=[pscustomobject]@{HasExited=$false}
            $process|Add-Member -MemberType ScriptMethod -Name Refresh -Value {}
            $complete=$false;$result=@();$nativeResult=@();$failure=$null
            try {
                . ([scriptblock]::Create($loops[0].Extent.Text))
                . ([scriptblock]::Create($gates[0].Extent.Text))
            } catch {$failure=$_.Exception.Message}
            $success=$mode -in @('late-zero','immediate')
            if($success -and (!$complete -or $failure)){throw "$entry/$mode did not complete: $failure"}
            if(!$success -and !$failure){throw "$entry/$mode accepted a missing/nonzero/fatal result"}
            $terminalReads=@($script:TerminalState.queries|Where-Object name -eq 'native-result-after-death')
            $expected=if($mode -in @('immediate','fatal','running')){0}else{1}
            if($terminalReads.Count -ne $expected){throw "$entry/$mode terminal read count is not $expected"}
            if($mode -eq 'fatal' -and $failure -notlike 'Fatal cleanup error:*'){throw 'Fatal lifecycle error was hidden'}
            if($mode -eq 'timeout' -and $failure -cne 'synthetic terminal query timeout'){throw 'Terminal query error was hidden'}
        }
    }
    Write-Output 'PASS: actual API10/API21 loops handle result/death race with bounded terminal read; missing/nonzero/timeout/fatal still fail'
} finally {
    if(Test-Path -LiteralPath $fixture){
        $resolved=(Resolve-Path -LiteralPath $fixture).Path
        if([IO.Path]::GetDirectoryName($resolved) -cne $parent){throw 'Unexpected terminal fixture cleanup path'}
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
