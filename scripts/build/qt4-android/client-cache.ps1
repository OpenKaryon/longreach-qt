# SPDX-License-Identifier: GPL-3.0-or-later
# Internal helpers; production callers use the platform's default path semantics.
function Get-Qt4ClientCacheIdentity([string]$Root,[string]$Abi,[bool]$CaseInsensitive=$IsWindows) {
    $canonical=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Root))
    $keyPath=if ($CaseInsensitive) { $canonical.ToLowerInvariant() } else { $canonical }
    $hasher=[Security.Cryptography.SHA256]::Create()
    try {
        $bytes=$hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($keyPath))
        $key=([BitConverter]::ToString($bytes)).Replace('-','').Substring(0,16).ToLowerInvariant()
    } finally { $hasher.Dispose() }
    $name="longreach-qt4-$Abi-clients-$key"
    return [pscustomobject]@{Volume=$name;Container=$name;Root=$canonical}
}

function Assert-Qt4ClientCacheIdle($Cache) {
    # Volume lookup also finds older producers that had no stable container name.
    $owners=@(& docker ps --all --filter "volume=$($Cache.Volume)" --format '{{.ID}} {{.Names}}')
    if ($LASTEXITCODE) { throw 'Cannot inspect Qt4 client cache owners' }
    if (@($owners | Where-Object { ![string]::IsNullOrWhiteSpace($_) }).Count) { throw "Qt4 client cache is busy: $($owners -join ', ')" }
    $slot=@(& docker ps --all --filter "name=^/$($Cache.Container)$" --format '{{.ID}} {{.Names}}')
    if ($LASTEXITCODE) { throw 'Cannot inspect the Qt4 client container slot' }
    if (@($slot | Where-Object { ![string]::IsNullOrWhiteSpace($_) }).Count) { throw "Qt4 client container slot is still present: $($slot -join ', ')" }
}
