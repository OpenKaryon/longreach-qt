# SPDX-License-Identifier: GPL-3.0-or-later
param([ValidateSet('armeabi-v7a','arm64-v8a')][string]$Abi = 'armeabi-v7a', [string]$RunName='sdk-suite', [ValidateSet('on','mesa')][string]$Gpu='on',
      [string[]]$CaseNames, [switch]$DebugQtPlugins, [ValidateSet('default','software')][string]$QtQuickBackend='default',
      [string]$AndroidSdk=$env:ANDROID_HOME, [string]$OutputDirectory)
& "$PSScriptRoot/android-api21-suite.ps1" -QtMajor 6 @PSBoundParameters
