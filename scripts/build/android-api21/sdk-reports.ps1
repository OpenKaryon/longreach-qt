# SPDX-License-Identifier: GPL-3.0-or-later
# Internal SDK export; the caller retains its artifact-root lease.
function Import-AndroidSdkReports {
    param([string]$Container,[string]$ProducerDirectory,[string]$OutputDirectory,
          [int]$QtMajor,[int]$Api,[string]$Abi,[string]$SdkImageId)
    $root=(New-Item -ItemType Directory -Force -Path $OutputDirectory).FullName
    $stage=(New-Item -ItemType Directory -Path (Join-Path $root ('.sdk-report-input-'+[guid]::NewGuid().ToString('N')))).FullName
    $complete=$false
    try {
        & docker cp "${Container}:${ProducerDirectory}/." $stage
        if ($LASTEXITCODE) { throw 'Cannot copy the immutable SDK producer directory' }
        & python "$PSScriptRoot/sdk-reports.py" export --source $stage --output $root --qt-major $QtMajor --abi $Abi --sdk-image-id $SdkImageId --artifact-lease-held
        if ($LASTEXITCODE) { throw 'Missing, incomplete or changed producer inventory; select a compatible SDK explicitly' }
        $complete=$true
    } catch { throw "Missing API$Api SDK producer reports or valid inventory. $($_.Exception.Message)" }
    finally {
        if ($complete) {
            $resolved=(Resolve-Path -LiteralPath $stage).Path
            if ([IO.Path]::GetDirectoryName($resolved) -ne $root -or [IO.Path]::GetFileName($resolved) -notlike '.sdk-report-input-*') { throw 'Unexpected report staging cleanup path' }
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
}
