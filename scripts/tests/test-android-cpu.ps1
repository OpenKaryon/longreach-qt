# SPDX-License-Identifier: GPL-3.0-or-later
<# CPU metadata capture/binding fixtures; no ADB, emulator or native probe. #>
param([string]$RepoRoot=(Resolve-Path "$PSScriptRoot/../..").Path)
$ErrorActionPreference='Stop'
. "$RepoRoot/scripts/run/android-cpu.ps1"
$parent=(New-Item -ItemType Directory -Force "$RepoRoot/build/fixtures").FullName
$fixture=Join-Path $parent ('android-cpu-'+[guid]::NewGuid())
$script:CpuFixturePython=(Get-Command python).Source
$script:CpuFixtureMutate=$false
function python {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    $lines=@(& $script:CpuFixturePython @Arguments)
    $exit=$LASTEXITCODE
    if ($script:CpuFixtureMutate -and !$exit) {
        [IO.File]::AppendAllText("$fixture/guest-cpuinfo.txt","`n")
        $script:CpuFixtureMutate=$false
    }
    $global:LASTEXITCODE=$exit
    return $lines
}
function Assert-Cpu([bool]$Condition,[string]$Message) { if (!$Condition) { throw $Message } }
function Expect-CpuFailure([scriptblock]$Action,[string]$Message) {
    try { & $Action } catch {
        Assert-Cpu ($_.Exception.Message -match $Message) "Unexpected CPU failure: $_"
        return
    }
    throw 'Expected CPU validation/binding refusal'
}
try {
    New-Item -ItemType Directory -Path $fixture | Out-Null
    $source=Join-Path $fixture 'guest-cpuinfo.txt'
    $valid="processor`t: 0`nflags`t: ssse3`n"
    [IO.File]::WriteAllText($source,$valid)
    $binding=Save-AndroidGuestCpuBaseline $fixture 'x86'
    Assert-AndroidGuestCpuBinding $fixture $binding
    $report=Get-Content "$fixture/guest-cpu-baseline.json" -Raw | ConvertFrom-Json
    Assert-Cpu ($report.required_flags.Count -eq 1 -and $report.required_flags[0] -eq 'ssse3') 'CPU policy added unrequired SSE4/AVX'
    python -c 'import importlib.util,pathlib,sys; s=importlib.util.spec_from_file_location("cpu",pathlib.Path(sys.argv[1])/"scripts/run/android-cpu.py"); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); m.validate(pathlib.Path(sys.argv[2]),"x86"); print("Python accepted the actual PowerShell CPU record")' $RepoRoot $fixture
    if ($LASTEXITCODE) { throw 'Python rejected the PowerShell CPU record' }
    $saved=[IO.File]::ReadAllText("$fixture/guest-cpu-baseline.json")
    [IO.File]::WriteAllText($source,"processor: 0`nflags: sse2`n")
    Expect-CpuFailure { Save-AndroidGuestCpuBaseline $fixture 'x86' } 'required evidence flags'
    Assert-Cpu ([IO.File]::ReadAllText("$fixture/guest-cpu-baseline.json") -ceq $saved) 'Failed CPU check overwrote the prior record'
    Expect-CpuFailure { Assert-AndroidGuestCpuBinding $fixture $binding } 'changed after validation'
    [IO.File]::WriteAllText($source,$valid)
    $script:CpuFixtureMutate=$true
    Expect-CpuFailure { Save-AndroidGuestCpuBaseline $fixture 'x86' } 'changed during validation'
    Assert-Cpu ([IO.File]::ReadAllText("$fixture/guest-cpu-baseline.json") -ceq $saved) 'Changed CPU capture published a new record'
    [IO.File]::WriteAllText($source,$valid)
    [IO.File]::AppendAllText("$fixture/guest-cpu-baseline.json","`n")
    Expect-CpuFailure { Assert-AndroidGuestCpuBinding $fixture $binding } 'changed after validation'
    Write-Output 'PASS: actual CPU validation/capture, Python/PowerShell JSON binding, missing SSSE3 and changed-file refusal'
} finally {
    Remove-Item Function:python -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $fixture) {
        $resolved=(Resolve-Path -LiteralPath $fixture).Path
        if ([IO.Path]::GetDirectoryName($resolved) -ne $parent -or [IO.Path]::GetFileName($resolved) -notlike 'android-cpu-*') { throw 'Unexpected CPU fixture cleanup path' }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
