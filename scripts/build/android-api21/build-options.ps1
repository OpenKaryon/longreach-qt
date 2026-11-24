# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
function Get-AndroidDockerBuildFlags {
    param([switch]$NoCache,[string]$DockerBuildFlagsJson='[]')
    $flags=ConvertFrom-Json -InputObject $DockerBuildFlagsJson -NoEnumerate
    if ($flags -isnot [array] -or @($flags | Where-Object { $_ -isnot [string] }).Count) {
        throw 'DockerBuildFlagsJson must be an array of strings'
    }
    if ($NoCache) { '--no-cache' }
    $flags
}


function New-AndroidBuildJobsFile {
    param([ValidateRange(1,256)][int]$Jobs=2)
    $path=[IO.Path]::GetTempFileName()
    [IO.File]::WriteAllText($path,[string]$Jobs,[Text.Encoding]::ASCII)
    return $path
}
