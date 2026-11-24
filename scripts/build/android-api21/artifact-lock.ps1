# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
function Enter-AndroidArtifactLock([string]$Root) {
    $path=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath((New-Item -ItemType Directory -Force -Path $Root).FullName))
    if ($global:LongreachArtifactLocks -isnot [Collections.Generic.Dictionary[string,IO.FileStream]]) {
        $comparer=if ($IsWindows) { [StringComparer]::OrdinalIgnoreCase } else { [StringComparer]::Ordinal }
        $locks=[Collections.Generic.Dictionary[string,IO.FileStream]]::new($comparer)
        if ($global:LongreachArtifactLocks) {
            foreach ($key in $global:LongreachArtifactLocks.Keys) { $locks[$key]=$global:LongreachArtifactLocks[$key] }
        }
        $global:LongreachArtifactLocks=$locks
    }
    if ($global:LongreachArtifactLocks.ContainsKey($path) -and $global:LongreachArtifactLocks[$path].CanRead) { return $null }
    try {
        $stream=[IO.File]::Open((Join-Path $path '.longreach-artifacts.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    } catch [IO.IOException] { throw "Another Longreach operation owns artifact directory: $path" }
    $global:LongreachArtifactLocks[$path]=$stream
    return $stream
}

function Get-AndroidArtifactLockStream([string]$Root) {
    $path=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Root))
    if (!$global:LongreachArtifactLocks -or !$global:LongreachArtifactLocks.ContainsKey($path) -or
            !$global:LongreachArtifactLocks[$path].CanRead) { throw 'Current PowerShell process does not own this artifact lease' }
    return $global:LongreachArtifactLocks[$path]
}

function Clear-AndroidResultAggregates([string]$Root) {
    foreach ($name in @('final-results.json','final-results-table.md','apk-native-abi-check.json',
            'apk-architecture-final.json','screenshots.json')) {
        [IO.File]::Delete((Join-Path $Root $name))
    }
}

function Get-AndroidVerifiedHash([string]$Path,[string]$ExpectedSha256) {
    $actual=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($ExpectedSha256 -notmatch '^[0-9a-f]{64}$' -or $actual -cne $ExpectedSha256) {
        throw "Artifact bytes differ from the recorded SHA256: $Path"
    }
    return $actual
}
