# SPDX-License-Identifier: GPL-3.0-or-later
. "$PSScriptRoot/android-adb-endpoint.ps1"
# Bounded ADB client calls. The daemon is shared and is never killed here.
function Get-AndroidAdbTimeoutMilliseconds([string[]]$Arguments) {
    $index=0
    while ($index -lt $Arguments.Count) {
        if ($Arguments[$index] -in @('-s','-t','-H','-P','-L')) { $index+=2;continue }
        if ($Arguments[$index] -in @('-a','-d','-e')) { $index++;continue }
        break
    }
    $command=if ($index -lt $Arguments.Count) { $Arguments[$index] } else { '' }
    if ($command -in @('install','install-multiple','install-multi-package','uninstall','push','pull','sync')) { return 180000 }
    if ($command -eq 'shell' -and $index+2 -lt $Arguments.Count) {
        if ($Arguments[$index+1] -eq 'pm' -and $Arguments[$index+2] -in @('install','uninstall')) { return 180000 }
        if ($Arguments[$index+1] -in @('am','pm')) { return 30000 }
    }
    return 15000
}
function New-AndroidAdbClientStartInfo([string]$Adb,[string[]]$Arguments,$Endpoint) {
    $info=[Diagnostics.ProcessStartInfo]::new($Adb)
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $info.StandardOutputEncoding=[Text.UTF8Encoding]::new($false)
    $info.StandardErrorEncoding=[Text.UTF8Encoding]::new($false)
    foreach ($argument in @(Get-AndroidAdbArguments -Arguments $Arguments -Endpoint $Endpoint)) { $info.ArgumentList.Add($argument) }
    return $info
}
function Start-AndroidAdbClientProcess([string]$Adb,[string[]]$Arguments,$Endpoint) {
    return [Diagnostics.Process]::Start((New-AndroidAdbClientStartInfo -Adb $Adb -Arguments $Arguments -Endpoint $Endpoint))
}
function ConvertFrom-AndroidAdbLines([string]$Text) {
    $reader=[IO.StringReader]::new($Text)
    try {
        while ($null -ne ($line=$reader.ReadLine())) { Write-Output $line }
    } finally { $reader.Dispose() }
}
function Invoke-AndroidAdb {
    param([Parameter(Mandatory)][string]$Adb,[AllowEmptyCollection()][string[]]$Arguments=@(),
          [ValidateRange(0,600000)][int]$TimeoutMilliseconds=0,[switch]$AllowNonzero,$Endpoint)
    if (!$TimeoutMilliseconds) { $TimeoutMilliseconds=Get-AndroidAdbTimeoutMilliseconds $Arguments }
    $process=$null
    $timer=[Diagnostics.Stopwatch]::StartNew()
    try {
        $process=Start-AndroidAdbClientProcess -Adb $Adb -Arguments $Arguments -Endpoint $Endpoint
        $stdout=$process.StandardOutput.ReadToEndAsync()
        $stderr=$process.StandardError.ReadToEndAsync()
        $left=[Math]::Max(0,$TimeoutMilliseconds-[int]$timer.ElapsedMilliseconds)
        if (!$process.WaitForExit($left)) { throw "ADB command timed out after $TimeoutMilliseconds ms: $($Arguments -join ' ')" }
        foreach ($task in @($stdout,$stderr)) {
            $left=[Math]::Max(0,$TimeoutMilliseconds-[int]$timer.ElapsedMilliseconds)
            if (!$task.Wait($left)) { throw "ADB command output did not close within $TimeoutMilliseconds ms: $($Arguments -join ' ')" }
        }
        if ($timer.ElapsedMilliseconds -ge $TimeoutMilliseconds) { throw "ADB command deadline elapsed: $($Arguments -join ' ')" }
        $code=$process.ExitCode
        $global:LASTEXITCODE=$code
        $output=$stdout.GetAwaiter().GetResult()
        $errorText=$stderr.GetAwaiter().GetResult()
        if ($code -ne 0) {
            if ($AllowNonzero) { return } # Failed result-file polls never turn stdout '0' into completion.
            $detail=$errorText.Trim()
            if ($detail.Length -gt 2048) { $detail=$detail.Substring(0,2048) }
            throw "adb failed with code $code`: $($Arguments -join ' '): $detail"
        }
        return @(ConvertFrom-AndroidAdbLines $output)
    } finally {
        if ($process) {
            try {
                if (!$process.HasExited) {
                    try { $process.Kill() } catch { if (!$process.WaitForExit(1000)) { throw } }
                    if (!$process.WaitForExit(1000)) { throw 'Owned ADB client did not stop' }
                }
            } finally { $process.Dispose() }
        }
    }
}
