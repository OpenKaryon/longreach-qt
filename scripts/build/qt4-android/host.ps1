# SPDX-License-Identifier: GPL-3.0-or-later

function Invoke-DonutCommand([string] $Program, [string[]] $Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program exited with code $LASTEXITCODE." }
}

function Expand-DonutInput([string] $Archive, [string] $Hash, [string] $Destination, [string] $Member) {
    $Archive = (Resolve-Path -LiteralPath $Archive).Path
    if ((Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash -ne $Hash) {
        throw "SHA256 mismatch for $Archive."
    }
    $Destination = (New-Item -ItemType Directory -Force -Path $Destination).FullName
    $extracted = Join-Path $Destination $Member
    if (!(Test-Path -LiteralPath "$extracted.$Hash")) {
        Invoke-DonutCommand tar.exe @('-xf', $Archive, '-C', $Destination) | Out-Host
        if (!(Test-Path -LiteralPath $extracted -PathType Leaf)) { throw "Missing $Member in $Archive." }
        New-Item -ItemType File -Force -Path "$extracted.$Hash" | Out-Null
    }
    return (Get-Item -LiteralPath $extracted).FullName
}
