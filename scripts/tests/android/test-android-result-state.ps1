# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
# Ordinary file-state/lease fixtures. Never starts adb, Docker or guests.
param([string]$RepoRoot=(Resolve-Path "$PSScriptRoot/../../..").Path)
$ErrorActionPreference='Stop'
. "$RepoRoot/scripts/build/android-api21/artifact-lock.ps1"
$parent=(New-Item -ItemType Directory -Force "$RepoRoot/build/fixtures").FullName
$fixture=Join-Path $parent ('android-result-state-'+[guid]::NewGuid())
$lease=$null
$child=$null
try {
    $root=(New-Item -ItemType Directory -Force "$fixture/artifacts").FullName
    $sdk=(New-Item -ItemType Directory -Force "$fixture/sdk").FullName
    $lease=Enter-AndroidArtifactLock $root
    foreach ($variant in @(($root+[IO.Path]::DirectorySeparatorChar),(Join-Path $root '.'))) {
        if (Enter-AndroidArtifactLock $variant) { throw 'Nested path variant replaced its parent lease' }
    }
    $apk=Join-Path $root 'example.apk'
    [IO.File]::WriteAllText($apk,'installed APK fixture')
    $sha=(Get-FileHash -LiteralPath $apk).Hash.ToLowerInvariant()
    if ((Get-AndroidVerifiedHash $apk $sha) -cne $sha) { throw 'APK hash was not captured' }
    $manifest=@{files=@{'apk/example.apk'=$sha}} | ConvertTo-Json -Depth 3 | ConvertFrom-Json
    $relative='apk/example.apk'
    if ((Get-AndroidVerifiedHash $apk ($manifest.files.PSObject.Properties[$relative].Value)) -cne $sha) {
        throw 'APK path was not matched to its manifest field'
    }
    [IO.File]::WriteAllText($apk,'APK replaced while running')
    $rejected=$false
    try { Get-AndroidVerifiedHash $apk $sha | Out-Null }
    catch { if ($_.Exception.Message -notlike 'Artifact bytes differ*') { throw }; $rejected=$true }
    if (!$rejected) { throw 'Changed APK was accepted as the installed input' }
    $reports=@('final-results.json','final-results-table.md','apk-native-abi-check.json','apk-architecture-final.json','screenshots.json')
    foreach ($name in $reports) { [IO.File]::WriteAllText((Join-Path $root $name),'old PASS') }
    Clear-AndroidResultAggregates $root
    foreach ($name in $reports) { if (Test-Path -LiteralPath (Join-Path $root $name)) { throw "Stale aggregate survived: $name" } }
    if (!(Test-Path -LiteralPath $apk)) { throw 'Invalidation removed saved APK data' }

    foreach ($runner in @('android-api21-suite.ps1','qt4-android-api21-suite.ps1','../build/qt4-android/package.ps1')) {
        $runnerPath=(Join-Path $RepoRoot "scripts/run/$runner").Replace("'","''")
        $rootLiteral=$root.Replace("'","''")
        $sdkLiteral=$sdk.Replace("'","''")
        $extra=if ($runner -like '*package.ps1') { "-Profile core -NativeDirectory '$rootLiteral' -AndroidJar '$sdkLiteral/android.jar'" } else { '' }
        $code="try { & '$runnerPath' -Abi x86_64 -OutputDirectory '$rootLiteral' -AndroidSdk '$sdkLiteral' $extra; exit 2 } catch { if (`$_.Exception.Message -like 'Another Longreach operation*') { exit 0 }; Write-Error `$_; exit 3 }"
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
        $start=@{FilePath=(Get-Command pwsh).Source;ArgumentList=@('-NoProfile','-EncodedCommand',$encoded);PassThru=$true}
        if ($IsWindows) { $start.WindowStyle='Hidden' }
        $child=Start-Process @start
        if (!$child.WaitForExit(15000)) { throw 'Standalone runner lock check timed out' }
        if ($child.ExitCode -ne 0) { throw "Standalone $runner did not reject an owned artifact root" }
    }
    # Python collectors and writers must use the same lease as PS producers.
    $python=(Get-Command python).Source
    $ownerReport=Join-Path $root 'final-results.json'
    [IO.File]::WriteAllText($ownerReport,'current owner report')
    foreach ($entry in @('scripts/build/android-api21/collect-results.py',
            'scripts/build/qt4-android/collect-api21-results.py',
            'scripts/build/qt5-android/collect-legacy-results.py',
            'scripts/build/android-api21/artifact-manifest.py',
            'scripts/build/qt4-android/artifact-manifest.py',
            'scripts/build/android-api21/sdk-reports.py')) {
        $program=Join-Path $RepoRoot $entry
        $arguments=@($program,'--root',$root,'--run','fixture-run','--abi','x86_64')
        if ($entry -like '*collect-legacy*') { $arguments=@($program,'--root',$root,'--run','fixture-run','--abi','x86') }
        if ($entry -like '*artifact-manifest*') { $arguments=@($program,'begin','--root',$root,'--abi','x86_64','--qt-major','6','--sdk-image-id',('sha256:'+('a'*64))) }
        if ($entry -like '*qt4-android/artifact-manifest.py') { $arguments=@($program,'check-apks','--root',$root,'--abi','x86_64') }
        if ($entry -like '*sdk-reports.py') { $arguments=@($program,'export','--source',(Join-Path $fixture 'input-reports'),'--output',$root,'--qt-major','6','--abi','x86_64','--sdk-image-id',('sha256:'+('a'*64))) }
        $log=@(& $python @arguments 2>&1)
        if ($LASTEXITCODE -eq 0 -or ($log -join "`n") -notlike '*Another Longreach operation*') {
            throw "Python entry did not reject the PS owner's lease: $entry : $log"
        }
        if ([IO.File]::ReadAllText($ownerReport) -cne 'current owner report') { throw 'Contender removed its owner report' }
    }
    # The real nested manifest command is allowed under its PS parent's lease;
    # it only reserves metadata, without compiling or invoking a guest.
    & $python "$RepoRoot/scripts/build/android-api21/artifact-manifest.py" begin --root $root --qt-major 6 --abi x86_64 --sdk-image-id ('sha256:'+('a'*64)) --artifact-lease-held | Out-Null
    if ($LASTEXITCODE) { throw 'Delegated manifest command deadlocked or failed' }
    if (!(Test-Path -LiteralPath "$root/examples-in-progress.json")) { throw 'Delegated command did not reserve a generation' }
    Write-Output 'PASS: aggregate invalidation, APK identity, normalized nested leases and standalone runner ownership'
} finally {
    if ($child -and !$child.HasExited) { Stop-Process -InputObject $child; $child.WaitForExit() }
    if ($lease) { $lease.Dispose() }
    if (Test-Path -LiteralPath $fixture) {
        $resolved=(Resolve-Path -LiteralPath $fixture).Path
        if ([IO.Path]::GetDirectoryName($resolved) -ne $parent) { throw 'Unexpected fixture cleanup path' }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
