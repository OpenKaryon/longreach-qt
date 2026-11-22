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
