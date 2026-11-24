# SPDX-License-Identifier: GPL-3.0-or-later
<# Cache identity and owner-query fixtures; Docker is a recording function. #>
#Requires -Version 7.0
param([string]$RepoRoot=(Resolve-Path "$PSScriptRoot/../..").Path)
$ErrorActionPreference='Stop'
. "$RepoRoot/scripts/build/qt4-android/client-cache.ps1"
function Assert-Cache([bool]$Condition,[string]$Message) { if (!$Condition) { throw $Message } }
$script:CacheCalls=[Collections.Generic.List[string]]::new()
$script:CacheVolumeOwner=''
$script:CacheNameOwner=''
$script:CacheFailure=''
function docker {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    $script:CacheCalls.Add($Arguments -join '|')
    Assert-Cache ($Arguments[0] -eq 'ps') 'Owner preflight attempted a mutation'
    $volume=@($Arguments | Where-Object { $_ -like 'volume=*' }).Count -eq 1
    $global:LASTEXITCODE=if (($volume -and $script:CacheFailure -eq 'volume') -or
        (!$volume -and $script:CacheFailure -eq 'name')) { 1 } else { 0 }
    Assert-Cache ($Arguments -contains '--all') 'Stopped or created cache owner was not checked'
    if ($volume) { return $script:CacheVolumeOwner }
    Assert-Cache ($Arguments -contains '--all') 'Stopped named container was not checked'
    return $script:CacheNameOwner
}
function Expect-CacheFailure([string]$Message) {
    try { Assert-Qt4ClientCacheIdle $cache } catch {
        Assert-Cache ($_.Exception.Message -match $Message) "Unexpected error: $_"
        return
    }
    throw 'Busy or unqueryable client cache was accepted'
}
try {
    $sample=Join-Path ([IO.Path]::GetTempPath()) 'LongreachCacheFixture'
    $folded=Get-Qt4ClientCacheIdentity $sample 'x86_64' $true
    $foldedAlias=Get-Qt4ClientCacheIdentity $sample.ToLowerInvariant() 'x86_64' $true
    Assert-Cache ($folded.Volume -eq $foldedAlias.Volume) 'Windows path case changed an existing cache name'
    $sensitive=Get-Qt4ClientCacheIdentity $sample 'x86_64' $false
    $sensitiveAlias=Get-Qt4ClientCacheIdentity $sample.ToLowerInvariant() 'x86_64' $false
    Assert-Cache ($sensitive.Volume -ne $sensitiveAlias.Volume) 'Distinct Unix paths shared one cache name'
    $hasher=[Security.Cryptography.SHA256]::Create()
    try {
        $legacy=([BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes(
            [IO.Path]::GetFullPath($sample).TrimEnd('\','/').ToLowerInvariant())))).Replace('-','').Substring(0,16).ToLowerInvariant()
    } finally { $hasher.Dispose() }
    Assert-Cache ($folded.Volume -eq "longreach-qt4-x86_64-clients-$legacy") 'Existing Windows cache suffix changed'
    $cache=$folded
    Assert-Qt4ClientCacheIdle $cache
    Assert-Cache ($script:CacheCalls.Count -eq 2) 'Idle preflight missed a query'
    Assert-Cache ($script:CacheCalls[0] -like "*volume=$($cache.Volume)*" -and
        $script:CacheCalls[1] -like "*name=^/$($cache.Container)`$*") 'Preflight inspected a different volume/container'
    $script:CacheVolumeOwner='old-client retained-cache-user'
    Expect-CacheFailure 'client cache is busy'
    $script:CacheVolumeOwner=''
    $script:CacheNameOwner='stopped-client retained-slot'
    Expect-CacheFailure 'container slot is still present'
    $script:CacheNameOwner=''
    foreach ($query in @('volume','name')) {
        $script:CacheFailure=$query
        Expect-CacheFailure 'Cannot inspect'
    }
    $script:CacheFailure=''
    $script:CacheVolumeOwner='  '
    $script:CacheNameOwner='  '
    Assert-Qt4ClientCacheIdle $cache
    Write-Output 'PASS: cache identity, retained owner/name refusal, query failure, no cache mutation'
} finally {
    Remove-Item Function:docker -ErrorAction SilentlyContinue
}
