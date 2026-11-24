# SPDX-License-Identifier: GPL-3.0-or-later
# Internal helper: the runner owns its artifact/run state and lease.
function Save-AndroidGuestCpuBaseline([string]$Directory,[string]$Abi) {
    $source=Join-Path $Directory 'guest-cpuinfo.txt'
    $report=Join-Path $Directory 'guest-cpu-baseline.json'
    $json=@(& python "$PSScriptRoot/android-cpu.py" --abi $Abi --cpuinfo $source 2>&1)
    if ($LASTEXITCODE) { throw ($json -join "`n") }
    $result=($json -join "`n") | ConvertFrom-Json
    if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -cne $result.guest_cpuinfo_sha256) {
        throw 'Guest CPU evidence changed during validation'
    }
    [IO.File]::WriteAllText($report,($json -join "`n")+"`n",[Text.UTF8Encoding]::new($false))
    return [pscustomobject]@{
        guest_cpuinfo_sha256=$result.guest_cpuinfo_sha256
        guest_cpu_baseline_sha256=(Get-FileHash -LiteralPath $report -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

function Assert-AndroidGuestCpuBinding([string]$Directory,$Binding) {
    foreach ($entry in @(@('guest-cpuinfo.txt','guest_cpuinfo_sha256'),@('guest-cpu-baseline.json','guest_cpu_baseline_sha256'))) {
        $expected=$Binding.($entry[1])
        if (!$expected -or (Get-FileHash -LiteralPath (Join-Path $Directory $entry[0]) -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expected) {
            throw 'Guest CPU evidence changed after validation'
        }
    }
}
