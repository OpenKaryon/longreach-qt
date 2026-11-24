# SPDX-License-Identifier: GPL-3.0-or-later
# Internal API10 case ownership, attempt history and selected-APK bindings.
. "$PSScriptRoot/android-adb.ps1"
function Invoke-AndroidTool([string]$Program,[string[]]$Arguments,$Endpoint,[int]$TimeoutMilliseconds=0) {
    if ([IO.Path]::GetFileNameWithoutExtension($Program) -ieq 'adb') {
        return (Invoke-AndroidAdb -Adb $Program -Arguments $Arguments -Endpoint $Endpoint -TimeoutMilliseconds $TimeoutMilliseconds)
    }
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program exited with code $LASTEXITCODE." }
}

function Get-AndroidCaseFullPath([string]$Path) {
    return [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Path))
}

function Test-AndroidCasePathEqual([string]$Left,[string]$Right) {
    $comparison=if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    return [string]::Equals((Get-AndroidCaseFullPath $Left),(Get-AndroidCaseFullPath $Right),$comparison)
}

function Test-AndroidCasePathWithin([string]$Child,[string]$Parent) {
    $relative=[IO.Path]::GetRelativePath((Get-AndroidCaseFullPath $Parent),(Get-AndroidCaseFullPath $Child))
    return !$relative.StartsWith('..'+[IO.Path]::DirectorySeparatorChar) -and $relative -ne '..' -and ![IO.Path]::IsPathRooted($relative)
}

function Get-AndroidApi10CaseRoots([string]$Apk,[string]$Directory,[string]$ArtifactRoot,[string]$BatchReceipt,[string]$CaseName) {
    $apkPath=Get-AndroidCaseFullPath $Apk
    $casePath=Get-AndroidCaseFullPath $Directory
    if ($BatchReceipt) {
        $batchPath=Get-AndroidCaseFullPath $BatchReceipt
        $batchDirectory=[IO.Path]::GetDirectoryName($batchPath)
        $batchRoot=[IO.Path]::GetDirectoryName($batchDirectory)
        if ([IO.Path]::GetFileName($batchPath) -cne 'batch-receipt.json' -or $CaseName -cnotmatch '^[a-z0-9-]+$' -or
                [IO.Path]::GetFileName($batchDirectory) -cnotmatch '^[a-z0-9-]+$' -or
                !(Test-AndroidCasePathEqual $casePath (Join-Path $batchDirectory $CaseName))) {
            throw 'API10 batch/case directory does not match its run and case name'
        }
        if ($ArtifactRoot -and !(Test-AndroidCasePathEqual $ArtifactRoot $batchRoot)) { throw 'ArtifactRoot differs from the API10 batch root' }
        $ArtifactRoot=$batchRoot
    } elseif (!$ArtifactRoot) {
        $parent=[IO.Path]::GetDirectoryName($apkPath)
        if ([IO.Path]::GetFileName($parent) -ieq 'extended' -and [IO.Path]::GetFileName([IO.Path]::GetDirectoryName($parent)) -ieq 'apk') {
            $ArtifactRoot=[IO.Path]::GetDirectoryName([IO.Path]::GetDirectoryName($parent))
        } elseif ([IO.Path]::GetFileName($parent) -ieq 'apk') { $ArtifactRoot=[IO.Path]::GetDirectoryName($parent) }
        else { $ArtifactRoot=$parent }
    }
    $ArtifactRoot=Get-AndroidCaseFullPath $ArtifactRoot
    if (!(Test-AndroidCasePathWithin $apkPath $ArtifactRoot)) { throw 'APK is outside its artifact root' }
    if ((Test-AndroidCasePathWithin $ArtifactRoot $casePath) -or (Test-AndroidCasePathEqual $casePath ([IO.Path]::GetPathRoot($casePath)))) {
        throw 'Case output must not contain the artifact root'
    }
    if (Test-Path -LiteralPath $casePath) {
        $item=Get-Item -LiteralPath $casePath -Force
        if (!$item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Case output must be an ordinary directory' }
    }
    return [pscustomobject]@{Root=$ArtifactRoot;Directory=$casePath;Apk=$apkPath}
}

function Assert-AndroidCaseInputsSeparate([string]$Directory,[string[]]$Inputs) {
    foreach ($path in $Inputs) {
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        if (Test-AndroidCasePathWithin $path $Directory) { throw 'Case output contains a protected APK/media input' }
        if ((Test-Path -LiteralPath $path -PathType Container) -and (Test-AndroidCasePathWithin $Directory $path)) {
            throw 'Case output must be separate from its media input directory'
        }
    }
    if ((Test-Path -LiteralPath $Directory) -and ((Get-Item -LiteralPath $Directory -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Case output is a reparse point' }
}

function Start-AndroidCaseAttempt([string]$Directory,[switch]$DeferArchive) {
    $casePath=Get-AndroidCaseFullPath (Resolve-Path -LiteralPath $Directory).Path
    $id=[guid]::NewGuid().ToString('N')
    $pending=Join-Path $casePath "attempt-$id.pending.json"
    $attempt=[ordered]@{schema_version=1;attempt_id=$id;started_utc=[DateTime]::UtcNow.ToString('o')}
    $stream=[IO.File]::Open($pending,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {
        $bytes=[Text.Encoding]::UTF8.GetBytes(($attempt | ConvertTo-Json)+"`n")
        $stream.Write($bytes,0,$bytes.Length)
    } finally { $stream.Dispose() }
    $state=[pscustomobject]@{Id=$id;Pending=$pending;History=$null;Directory=$casePath;StartedUtc=$attempt.started_utc;Archived=$false}
    if (!$DeferArchive) { Save-AndroidCaseAttemptHistory $state }
    return $state
}

function Save-AndroidCaseAttemptHistory($Attempt) {
    $casePath=$Attempt.Directory
    if ($Attempt.Id -cnotmatch '^[0-9a-f]{32}$' -or !(Test-AndroidCasePathEqual $Attempt.Pending (Join-Path $casePath "attempt-$($Attempt.Id).pending.json")) -or
            !(Test-Path -LiteralPath $Attempt.Pending -PathType Leaf)) { throw 'Missing current case attempt' }
    $items=@(Get-ChildItem -LiteralPath $casePath -Force | Where-Object {
        !(Test-AndroidCasePathEqual $_.FullName $Attempt.Pending) -and
        !(Test-AndroidCasePathEqual $_.FullName (Join-Path $casePath '.longreach-artifacts.lock')) -and
        !($_.PSIsContainer -and $_.Name -cmatch '^previous-(?:[0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$')
    })
    foreach ($item in $items) {
        if (!(Test-AndroidCasePathEqual ([IO.Path]::GetDirectoryName($item.FullName)) $casePath) -or
                ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Invalid existing case history entry' }
    }
    $history=$null
    if ($items.Count) {
        $history=Join-Path $casePath ("previous-$($Attempt.Id)")
        if (!(Test-AndroidCasePathEqual ([IO.Path]::GetDirectoryName($history)) $casePath)) { throw 'Invalid case history destination' }
        [IO.Directory]::CreateDirectory($history) | Out-Null
        foreach ($item in $items) {
            $destination=Join-Path $history $item.Name
            if (!(Test-AndroidCasePathWithin $destination $history) -or !(Test-AndroidCasePathWithin $item.FullName $casePath)) { throw 'Case history move leaves its directory' }
            Move-Item -LiteralPath $item.FullName -Destination $destination
        }
    }
    $Attempt.History=$history
    $Attempt.Archived=$true
}

function Write-AndroidCaseAttemptFailure($Attempt,[string]$Message) {
    if (Test-Path -LiteralPath $Attempt.Pending -PathType Leaf) {
        $failure=[ordered]@{schema_version=1;attempt_id=$Attempt.Id;started_utc=$Attempt.StartedUtc;
            failed=$true;failed_utc=[DateTime]::UtcNow.ToString('o');error_message=$Message}
        [IO.File]::WriteAllText($Attempt.Pending,($failure | ConvertTo-Json)+"`n",[Text.UTF8Encoding]::new($false))
    }
}

function Write-AndroidCaseReceipt([string]$Directory,$Receipt) {
    $path=Join-Path $Directory 'input-receipt.json'
    $temporary=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try {
        [IO.File]::WriteAllText($temporary,($Receipt | ConvertTo-Json -Depth 8)+"`n",[Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporary,$path,$true)
    } finally { [IO.File]::Delete($temporary) }
}

function Get-AndroidApi10ApkBinding([string]$Root,[string]$Apk,[string]$Abi,[string]$SdkImageId,[bool]$RequireManifest,[bool]$RuntimeProbe) {
    $manifestPath=Join-Path $Root 'apk-manifest.json'
    $binding=@{apk_sha256=(Get-FileHash -LiteralPath $Apk -Algorithm SHA256).Hash.ToLowerInvariant();
        apk_manifest_bound=$false;apk_manifest_sha256=$null;apk_relative=$null;sdk_image_id=$SdkImageId}
    if ($RuntimeProbe) {
        if ($RequireManifest) { throw 'RuntimeProbe cannot be a qualified Qt5 batch case' }
        return $binding
    }
    if (!(Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        if ($RequireManifest) { throw 'This API10 run requires its APK manifest' }
        return $binding
    }
    $manifestSha=(Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifest=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $relative=[IO.Path]::GetRelativePath($Root,$Apk).Replace('\','/')
    $comparison=if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    $entries=@($manifest.files.PSObject.Properties | Where-Object { [string]::Equals($_.Name,$relative,$comparison) })
    if (!$entries.Count -and !$RequireManifest) { return $binding }
    if ($entries.Count -ne 1 -or ($RequireManifest -and $manifest.schema_version -ne 2) -or
            $manifest.abi -cne $Abi -or $manifest.qt_major -ne 5 -or
            $manifest.sdk_image_id -cnotmatch '^sha256:[0-9a-f]{64}$' -or
            ($SdkImageId -and $manifest.sdk_image_id -cne $SdkImageId)) { throw 'API10 APK manifest does not match the selected APK/SDK/ABI' }
    Get-AndroidVerifiedHash $Apk $entries[0].Value | Out-Null
    Get-AndroidVerifiedHash $manifestPath $manifestSha | Out-Null
    $binding.apk_manifest_bound=$true
    $binding.apk_manifest_sha256=$manifestSha
    $binding.apk_relative=$entries[0].Name
    $binding.sdk_image_id=$manifest.sdk_image_id
    return $binding
}

function Assert-AndroidApi10ApkBinding([string]$Root,[string]$Apk,$Binding) {
    Get-AndroidVerifiedHash $Apk $Binding.apk_sha256 | Out-Null
    if ($Binding.apk_manifest_bound) { Get-AndroidVerifiedHash (Join-Path $Root 'apk-manifest.json') $Binding.apk_manifest_sha256 | Out-Null }
}
