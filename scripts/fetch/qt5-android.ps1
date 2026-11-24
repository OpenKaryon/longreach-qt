# SPDX-License-Identifier: GPL-3.0-or-later

param(
    [ValidateSet('armeabi-v7a','arm64-v8a','x86','x86_64')][string] $Abi = 'armeabi-v7a',
    [ValidateSet('all','sdk','test')][string] $Scope = 'all',
    [string] $OutputDirectory,
    [string] $AndroidSdk = $env:ANDROID_HOME,
    [switch] $PlatformOnly
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path "$PSScriptRoot/../..").Path
if (!$OutputDirectory) { $OutputDirectory = Join-Path $repo 'downloads/android-gingerbread' }
$output = (New-Item -ItemType Directory -Path $OutputDirectory -Force).FullName
$lock = Get-Content -LiteralPath "$PSScriptRoot/locks/qt5-android-api10-inputs.json" -Raw | ConvertFrom-Json
if ($Abi -notin @('armeabi-v7a','x86')) {
    & "$PSScriptRoot/qt6-android.ps1" -Abi $Abi -Scope $Scope -PlatformOnly -AndroidSdk $AndroidSdk
    if ($Scope -eq 'test') { return }
}
# API10 SDKs must also check forward symbol availability against pinned API21.
# Fetch only the shared platform archive; do not fetch an emulator or Qt6 SDK.
if ($Abi -in @('armeabi-v7a','x86') -and $Scope -ne 'test') {
    $forwardLock = Get-Content -LiteralPath "$PSScriptRoot/locks/qt6-android-api21-inputs.json" -Raw | ConvertFrom-Json
    $forwardInputs = @($forwardLock.sources | Where-Object { $_.file -ceq 'android-ndk-r27-linux.zip' })
    if ($forwardInputs.Count -ne 1) { throw 'Expected one pinned NDK API21 symbol input.' }
    $forwardInput = $forwardInputs[0]
    & python "$PSScriptRoot/fetch.py" $forwardInput.url "$repo/downloads/android-lollipop/$($forwardInput.file)" $forwardInput.sha256
    if ($LASTEXITCODE) { throw 'Could not fetch the API21 forward-symbol platform input.' }
}
$testInputs = @('android-2.3.3_r02-linux.zip','kernel-qemu-armv7','tools_r24.4.1-windows.zip','x86-10_r05.zip')
foreach ($source in $lock.sources) {
    if ($Abi -notin @('armeabi-v7a','x86') -and $source.file -ne 'android-35.jar') { continue }
    if ($source.abis -and $Abi -notin $source.abis) { continue }
    $forTest = $source.file -in $testInputs
    if (($Scope -eq 'sdk' -and $forTest) -or ($Scope -eq 'test' -and !$forTest)) { continue }
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

if ($Scope -eq 'test' -or $PlatformOnly) { return }
foreach ($source in $lock.shared_sources) {
    & python "$PSScriptRoot/fetch.py" $source.url "$repo/downloads/$($source.file)" $source.sha256
    if ($LASTEXITCODE) { throw "Could not fetch $($source.file)" }
}
