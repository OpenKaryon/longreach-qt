# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
function Select-AndroidImageFormats([string]$Directory, [string]$Abi, [string[]]$Keep) {
    if (!$Keep) { return }
    if ($Abi -notin @('armeabi-v7a','arm64-v8a','x86','x86_64') -or @($Keep | Where-Object { $_ -notmatch '^[a-z0-9]+$' }).Count) {
        throw 'Invalid Android image-plugin selection'
    }
    foreach ($file in Get-ChildItem -LiteralPath $Directory -File) {
        if ($file.Name -match ('^libplugins_imageformats_q([a-z0-9]+)_' + [regex]::Escape($Abi) + '\.so$') -and $Matches[1] -notin $Keep) {
            Remove-Item -LiteralPath $file.FullName
        }
    }
}


function Get-AndroidExampleMetadata([string]$App) {
    # Retain the package workaround for historical selftest suspension stalls.
    # It disables Qt dispatcher suspension; it does not qualify normal Activity
    # pause/resume behavior. The synchronous main alone does not establish cause.
    if ($App -eq 'qt-selftest') {
        return '<meta-data android:name="android.app.background_running" android:value="true"/>'
    }
    return ''
}
