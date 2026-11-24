# SPDX-License-Identifier: GPL-3.0-or-later

. "$PSScriptRoot/../android-api21/packaging-host.ps1"

function Invoke-DonutCommand([string] $Program, [string[]] $Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program exited with code $LASTEXITCODE." }
}

function Expand-DonutInput([string] $Archive, [string] $Hash, [string] $Destination, [string] $Member) {
    $Archive=(Resolve-Path -LiteralPath $Archive).Path
    $Destination=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Destination))
    if ([IO.Path]::GetFileName($Destination) -cne 'inputs') { throw 'API4 media destination must be the artifact root inputs directory' }
    $mediaArtifactRoot=[IO.Path]::GetDirectoryName($Destination)
    . "$PSScriptRoot/../android-api21/artifact-lock.ps1"
    . "$PSScriptRoot/../../run/android-owned-process.ps1"
    Assert-AndroidOwnedArtifactRootAvailable $mediaArtifactRoot
    $mediaLease=Enter-AndroidArtifactLock $mediaArtifactRoot
    try {
        Invoke-DonutCommand python @("$PSScriptRoot/prepare-media.py",'extract','--archive',$Archive,
            '--sha256',$Hash,'--destination',$Destination,'--member',$Member,'--artifact-lease-held') | Out-Null
        return (Get-Item -LiteralPath (Join-Path $Destination $Member)).FullName
    } finally { if ($mediaLease) { $mediaLease.Dispose() } }
}

function Initialize-DonutSigningKey([string]$OutputDirectory,[string]$JavaDirectory) {
    $keyStore=Join-Path $OutputDirectory 'local-probe.jks'
    if (!(Test-Path -LiteralPath $keyStore)) {
        $keytool=if ($JavaDirectory) { "$JavaDirectory/keytool.exe" } else { (Get-AndroidPackagingJava).keytool }
        Invoke-DonutCommand $keytool @('-genkeypair', '-keystore', $keyStore,
            '-storepass', 'donut-probe-local', '-keypass', 'donut-probe-local', '-alias', 'local-probe',
            '-keyalg', 'RSA', '-keysize', '2048', '-dname', 'CN=Local Android Probe', '-validity', '365') | Out-Host
    }
    return (Get-Item -LiteralPath $keyStore).FullName
}
