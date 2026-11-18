# SPDX-License-Identifier: GPL-3.0-or-later

param(
    [string] $OutputDirectory,
    [string] $AndroidSdk = $env:ANDROID_HOME
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot/../..").Path
if (!$OutputDirectory) { $OutputDirectory = Join-Path $repo 'downloads/android-lollipop' }
$output = (New-Item -ItemType Directory -Path $OutputDirectory -Force).FullName
$lock = Get-Content -LiteralPath "$PSScriptRoot/locks/qt6-android-api21-inputs.json" -Raw | ConvertFrom-Json
foreach ($source in $lock.sources) {
    $destination = Join-Path $output $source.file
    if (!(Test-Path -LiteralPath $destination)) {
        $temporary = Join-Path $output ($source.file + '.' + [guid]::NewGuid() + '.download')
        try {
            if ($source.encoding -eq 'installed') {
                if (!$AndroidSdk) { throw 'Set ANDROID_HOME or pass -AndroidSdk with Android platform 35 installed.' }
                Copy-Item -LiteralPath (Join-Path $AndroidSdk $source.installed_sdk_path) -Destination $temporary
            } elseif ($source.encoding -eq 'base64') {
                $encoded = (Invoke-WebRequest -Uri $source.url).Content
                [IO.File]::WriteAllBytes($temporary, [Convert]::FromBase64String($encoded))
            } else {
                Invoke-WebRequest -Uri $source.url -OutFile $temporary
            }
            if ((Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash -ne $source.sha256) {
                throw "SHA256 mismatch for $($source.file)."
            }
            Move-Item -LiteralPath $temporary -Destination $destination
        } finally {
            if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
        }
    }
    if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $source.sha256) {
        throw "SHA256 mismatch for existing $destination."
    }
    Write-Output "$($source.file): verified"
}

# The source archives use the shared verified fetcher and download lock.
foreach ($source in $lock.shared_sources) {
    & python "$PSScriptRoot/fetch.py" $source.url "$repo/downloads/$($source.file)" $source.sha256
    if ($LASTEXITCODE) { throw "Could not fetch $($source.file)" }
}
