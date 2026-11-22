# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
function Enter-AndroidArtifactLock([string]$Root) {
    $path=(New-Item -ItemType Directory -Force -Path $Root).FullName
    if (!$global:LongreachArtifactLocks) { $global:LongreachArtifactLocks=@{} }
    if ($global:LongreachArtifactLocks.ContainsKey($path) -and $global:LongreachArtifactLocks[$path].CanRead) { return $null }
    try {
        $stream=[IO.File]::Open((Join-Path $path '.longreach-artifacts.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    } catch [IO.IOException] { throw "Another Longreach operation owns artifact directory: $path" }
    $global:LongreachArtifactLocks[$path]=$stream
    return $stream
}
