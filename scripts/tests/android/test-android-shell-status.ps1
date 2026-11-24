# SPDX-License-Identifier: GPL-3.0-or-later
# Actual shell-status helper, recorded ADB, and bounded host Bash builtins only.
param([string]$RepoRoot=(Resolve-Path "$PSScriptRoot/../../..").Path)
$ErrorActionPreference='Stop'
. "$RepoRoot/scripts/run/android/android-shell-status.ps1"
$parent=(New-Item -ItemType Directory -Force "$RepoRoot/build/fixtures").FullName
$fixture=Join-Path $parent ('shell-status-'+[guid]::NewGuid())
$bash=if ($IsWindows) { 'C:/Program Files/Git/bin/bash.exe' } else { (Get-Command bash -CommandType Application -ErrorAction Stop).Source }
if (!(Test-Path -LiteralPath $bash)) { throw 'Bash required for ordinary shell-status fixtures' }
$savedLastExit=$global:LASTEXITCODE
$global:AndroidShellFixture=@{Mode='';Bash=$bash;LastMarker='';Markers=[Collections.Generic.HashSet[string]]::new();ActualExit=$null;Wrapped='';Calls=0}
function Assert-ShellStatus([bool]$Condition,[string]$Message) { if (!$Condition) { throw $Message } }
function Invoke-AndroidApi21Adb {
    param($Adb,$Serial,[string[]]$Parameters,[int]$TimeoutMilliseconds)
    $context=$global:AndroidShellFixture
    Assert-ShellStatus ($Adb -ceq 'recorded-adb' -and $Serial -ceq 'recorded-serial') 'Changed device binding'
    Assert-ShellStatus ($Parameters.Count -eq 2 -and $Parameters[0] -ceq 'shell' -and $TimeoutMilliseconds -eq 15000) 'Shell status lost exact argv or deadline'
    Assert-ShellStatus ($Parameters[1] -cmatch 'LONGREACH_SHELL_[a-f0-9]{32}') 'No per-invocation marker in shell source'
    $marker=$Matches[0]
    Assert-ShellStatus ($context.Markers.Add($marker)) 'Shell status reused an earlier attempt marker'
    $previous=$context.LastMarker;$context.LastMarker=$marker;$context.Wrapped=$Parameters[1];$context.Calls++
    $global:LASTEXITCODE=0
    switch ($context.Mode) {
        'ready' { 'ordinary output';"${marker}:0";return }
        'remote' { 'remote error';"${marker}:7";return }
        'host' { $global:LASTEXITCODE=1;"${marker}:0";return }
        'empty' { return }
        'missing' { 'ordinary output';return }
        'stale' { "${previous}:0";return }
        'duplicate' { "${marker}:0";"${marker}:0";return }
        'conflict' { "${marker}:0";"${marker}:7";return }
        'leading-zero' { "${marker}:00";return }
        'suffix' { "${marker}:0 garbage";return }
        'prefix' { " ${marker}:0";return }
        'negative' { "${marker}:-1";return }
        'overflow' { "${marker}:256";return }
        'truncated' { "${marker}:";return }
        'client-throws' { throw 'Recorded setup client failure' }
        'real-shell' {
            $process=$null
            try {
                $info=[Diagnostics.ProcessStartInfo]::new($context.Bash)
                $info.UseShellExecute=$false;$info.CreateNoWindow=$true
                $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
                $info.StandardOutputEncoding=[Text.UTF8Encoding]::new($false)
                foreach ($argument in @('--noprofile','--norc','-c',$Parameters[1])) { $info.ArgumentList.Add($argument) }
                $process=[Diagnostics.Process]::Start($info)
                $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
                Assert-ShellStatus ($process.WaitForExit(5000)) 'Ordinary host shell did not finish'
                Assert-ShellStatus ($stdout.Wait(1000) -and $stderr.Wait(1000)) 'Host shell pipes did not close'
                $context.ActualExit=$process.ExitCode
                Assert-ShellStatus (!$stderr.GetAwaiter().GetResult()) 'Unexpected host shell stderr'
                $reader=[IO.StringReader]::new($stdout.GetAwaiter().GetResult())
                try { while ($null -ne ($line=$reader.ReadLine())) { Write-Output $line } } finally { $reader.Dispose() }
                # Model legacy ADB host success independently of remote exit.
                $global:LASTEXITCODE=0
                return
            } finally {
                if ($process) {
                    try {
                        if (!$process.HasExited) { $process.Kill();Assert-ShellStatus ($process.WaitForExit(1000)) 'Retained host shell did not stop' }
                    } finally { $process.Dispose() }
                }
            }
        }
        default { throw 'Unexpected shell fixture mode' }
    }
}
function Invoke-StatusFixture([string]$Command='true') {
    Invoke-AndroidSetupCommand -Adb recorded-adb -Serial recorded-serial -Step fixture -Command $Command -OutputPath "$fixture/setup.stdout"
}
try {
    New-Item -ItemType Directory -Path $fixture | Out-Null
    $context=$global:AndroidShellFixture
    $context.Mode='ready'
    $output=@(Invoke-StatusFixture)
    Assert-ShellStatus ($output.Count -eq 1 -and $output[0] -ceq 'ordinary output') 'Helper lost ordinary output or returned its private marker'
    foreach ($mode in @('remote','host','empty','missing','stale','duplicate','conflict','leading-zero','suffix','prefix','negative','overflow','truncated','client-throws')) {
        $context.Mode=$mode
        $errorText=''
        try { Invoke-StatusFixture | Out-Null } catch { $errorText=$_.Exception.Message }
        $pattern=switch ($mode) {
            'remote' { 'Remote Android setup fixture failed with status 7' }
            'host' { 'ADB client failed with status 1' }
            'client-throws' { 'Recorded setup client failure' }
            default { 'Missing or invalid Android setup status marker' }
        }
        Assert-ShellStatus ($errorText -match $pattern) "Unexpected $mode outcome: $errorText"
        Assert-ShellStatus (Test-Path -LiteralPath "$fixture/setup.stdout") 'Setup attempt has no diagnostic file'
        if ($mode -in @('empty','client-throws')) { Assert-ShellStatus ((Get-Item -LiteralPath "$fixture/setup.stdout").Length -eq 0) 'Empty or failed response preserved a previous success transcript' }
    }
    $realCases=@(
        @{Command='true';Exit=0;Output=''},
        @{Command='false';Exit=1;Output=''},
        @{Command='printf without-newline';Exit=0;Output='without-newline'},
        @{Command='printf ''spaces and Кириллица''';Exit=0;Output='spaces and Кириллица'},
        @{Command='printf before-exit; exit 7';Exit=7;Output=''},
        @{Command='exit 255';Exit=255;Output=''},
        @{Command='false && printf must-not-run';Exit=1;Output=''},
        @{Command='false || true';Exit=0;Output=''}
    )
    foreach ($case in $realCases) {
        $context.Mode='real-shell';$context.ActualExit=$null
        $errorText='';$output=@()
        try { $output=@(Invoke-StatusFixture $case.Command) } catch { $errorText=$_.Exception.Message }
        Assert-ShellStatus ($context.ActualExit -eq $case.Exit) "Shell source did not preserve exit status: $($case.Command)"
        if ($case.Exit) { Assert-ShellStatus ($errorText -match "Remote Android setup fixture failed with status $($case.Exit)") 'Remote failure became success through legacy host status' }
        else {
            Assert-ShellStatus (!$errorText) "Successful host shell was refused: $errorText"
            if ($case.Output) { Assert-ShellStatus ($output -contains $case.Output) 'Shell source lost output or Unicode' }
        }
    }
    Write-Output "PASS: 15 recorded status cases and $($realCases.Count) bounded host Bash cases; exact argv/deadline, transcript, unique marker and remote/host status; no Android tools"
} finally {
    $global:LASTEXITCODE=$savedLastExit
    Remove-Variable AndroidShellFixture -Scope Global -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $fixture) {
        $resolved=(Resolve-Path -LiteralPath $fixture).Path
        if ([IO.Path]::GetDirectoryName($resolved) -ne $parent -or [IO.Path]::GetFileName($resolved) -notlike 'shell-status-*') { throw 'Unexpected fixture cleanup path' }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
