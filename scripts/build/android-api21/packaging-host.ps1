# SPDX-License-Identifier: GPL-3.0-or-later
# Shared Java selection and development-key initialization for host APK packaging.
function Invoke-AndroidPackagingTool([string]$Program,[string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE) { throw "$Program exited with code $LASTEXITCODE" }
}

function Get-AndroidPackagingJava([string]$Javac) {
    if (!$Javac) {
        $command=Get-Command javac.exe,javac -ErrorAction SilentlyContinue | Select-Object -First 1
        if (!$command) { throw 'Missing javac on PATH' }
        $Javac=$command.Source
    }
    $description=@(& python "$PSScriptRoot/host-tools.py" java-home --javac $Javac)
    if ($LASTEXITCODE) { throw 'Cannot resolve the actual packaging JDK' }
    $tools=($description -join "`n") | ConvertFrom-Json
    if (!$tools.launcher -or !$tools.javac -or !$tools.keytool -or !$tools.home) { throw 'Incomplete packaging JDK description' }
    return $tools
}

function Initialize-AndroidExamplesKey([string]$OutputDirectory,$JavaTools) {
    $directory=(New-Item -ItemType Directory -Force -Path $OutputDirectory).FullName
    $keyStore=Join-Path $directory 'local-examples.jks'
    if (!(Test-Path -LiteralPath $keyStore)) {
        if (!$JavaTools) { $JavaTools=Get-AndroidPackagingJava }
        Invoke-AndroidPackagingTool $JavaTools.keytool @('-genkeypair','-keystore',$keyStore,
            '-storepass','longreach-local','-keypass','longreach-local','-alias','examples',
            '-keyalg','RSA','-keysize','2048','-dname','CN=Local Longreach Examples','-validity','365') | Out-Host
    }
    if (!(Test-Path -LiteralPath $keyStore -PathType Leaf)) { throw 'Missing initialized examples signing key' }
    return (Get-Item -LiteralPath $keyStore).FullName
}


function Save-AndroidApkHistory {
    param([Parameter(Mandatory)][string]$Apk,[Parameter(Mandatory)][string]$HistoryDirectory)
    $sha=(Get-FileHash -LiteralPath $Apk -Algorithm SHA256).Hash.ToLowerInvariant()
    $directory=(New-Item -ItemType Directory -Force -Path (Join-Path $HistoryDirectory $sha)).FullName
    $destination=Join-Path $directory ([IO.Path]::GetFileName($Apk))
    if (!(Test-Path -LiteralPath $destination)) { Copy-Item -LiteralPath $Apk -Destination $destination }
    if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant() -cne $sha) {
        throw 'Saved APK history differs from its content hash'
    }
    # Keep the current APK until packaging replaces it successfully. Existing
    # UUID-named historical files remain untouched; no automatic purge runs.
}
