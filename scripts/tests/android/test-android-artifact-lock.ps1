# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
param([string]$RepoRoot=(Resolve-Path "$PSScriptRoot/../../..").Path)
$ErrorActionPreference='Stop'
. "$RepoRoot/scripts/build/android-api21/artifact-lock.ps1"
$parent=(New-Item -ItemType Directory -Force "$RepoRoot/build/fixtures").FullName
$fixture=Join-Path $parent ('android-lock-'+[guid]::NewGuid())
$lock=$null
$child=$null
try {
    $lock=Enter-AndroidArtifactLock $fixture
    $nested=Enter-AndroidArtifactLock $fixture
    if($nested){throw 'Nested operation replaced its parent lease'}
    $helper="$RepoRoot/scripts/build/android-api21/artifact-lock.ps1".Replace("'","''")
    $quoted=$fixture.Replace("'","''")
    $code=". '$helper'; try { Enter-AndroidArtifactLock '$quoted' | Out-Null; exit 2 } catch { if (`$_.Exception.Message -like 'Another Longreach*') { exit 0 }; exit 3 }"
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
    $options=@{FilePath=(Get-Command pwsh).Source;ArgumentList=@('-NoProfile','-EncodedCommand',$encoded);PassThru=$true}
    if($IsWindows){$options.WindowStyle='Hidden'}
    $child=Start-Process @options
    if(!$child.WaitForExit(10000)){throw 'Lock contender did not terminate'}
    if($child.ExitCode -ne 0){throw 'Concurrent process entered the artifact root'}
    $lock.Dispose();$lock=$null
    $lock=Enter-AndroidArtifactLock $fixture
    if(!$lock){throw 'Completed owner did not release its lease'}
    Write-Output 'PASS: process-exclusive artifact lease, nested phases and release after completion'
} finally {
    if($child -and !$child.HasExited){Stop-Process -InputObject $child;$child.WaitForExit()}
    if($lock){$lock.Dispose()}
    if(Test-Path $fixture){$resolved=(Resolve-Path $fixture).Path;if([IO.Path]::GetDirectoryName($resolved) -ne $parent){throw 'Unexpected fixture cleanup path'};Remove-Item -LiteralPath $resolved -Recurse -Force}
}
