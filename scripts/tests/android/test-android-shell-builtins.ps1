# SPDX-License-Identifier: GPL-3.0-or-later
# Run the actual status wrapper with shell builtins only, as on legacy Android.
param([string]$RepoRoot=(Resolve-Path "$PSScriptRoot/../../..").Path)
$ErrorActionPreference='Stop'
. "$RepoRoot/scripts/run/android/android-shell-status.ps1"
$bash=if($IsWindows){'C:/Program Files/Git/bin/bash.exe'}else{(Get-Command bash).Source}
$parent=(New-Item -ItemType Directory -Force "$RepoRoot/build/fixtures").FullName
$fixture=Join-Path $parent ('shell-builtins-'+[guid]::NewGuid())
New-Item -ItemType Directory -Path $fixture | Out-Null
function Invoke-AndroidApi21Adb {
    param($Adb,$Serial,[string[]]$Parameters,$TimeoutMilliseconds)
    $info=[Diagnostics.ProcessStartInfo]::new($bash)
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $info.StandardOutputEncoding=[Text.UTF8Encoding]::new($false)
    foreach($argument in @('--noprofile','--norc','-c',('enable -n printf; PATH=; '+$Parameters[1]))){$info.ArgumentList.Add($argument)}
    $process=[Diagnostics.Process]::Start($info)
    try {
        $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        if(!$process.WaitForExit(5000)){throw 'Builtins fixture exceeded its deadline'}
        if(!$stdout.Wait(1000) -or !$stderr.Wait(1000)){throw 'Builtins fixture pipes stayed open'}
        if($process.ExitCode -or $stderr.GetAwaiter().GetResult()){throw 'Successful builtin command failed'}
        $global:LASTEXITCODE=0
        $stdout.GetAwaiter().GetResult() -split '\r?\n' | Where-Object { $_ -ne '' }
    } finally {
        if(!$process.HasExited){$process.Kill();$process.WaitForExit(1000) | Out-Null}
        $process.Dispose()
    }
}
try {
    foreach($value in @('ordinary output','spaces and Кириллица')) {
        $output=@(Invoke-AndroidSetupCommand -Adb recorded-adb -Serial recorded-serial -Step fixture -Command ("echo -n '$value'") -OutputPath "$fixture/setup.stdout")
        if($output.Count -ne 1 -or $output[0] -cne $value){throw 'Builtin wrapper lost output or failed to validate remote success'}
    }
    Write-Output 'PASS: two successful shell-status executions without printf or external tools'
} finally {
    $resolved=(Resolve-Path -LiteralPath $fixture).Path
    if([IO.Path]::GetDirectoryName($resolved) -ne $parent -or [IO.Path]::GetFileName($resolved) -notlike 'shell-builtins-*'){throw 'Unexpected fixture cleanup path'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
