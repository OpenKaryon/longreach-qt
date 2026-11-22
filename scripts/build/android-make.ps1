# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#Requires -Version 7.0
param(
    [Parameter(Mandatory)][ValidateSet(4,5,6)][int]$QtMajor,
    [Parameter(Mandatory)][string]$OptionsJson
)
$ErrorActionPreference='Stop'
$options=ConvertFrom-Json -InputObject $OptionsJson -AsHashtable
if ($options -isnot [Collections.IDictionary]) { throw 'Expected an Android option object' }
$mode=if ($options.ContainsKey('Mode')) { $options.Mode } else { 'legacy' }
if ($mode -notin @('sdk','examples','legacy')) { throw 'Expected SDK or ready-APK examples mode' }
if ($mode -eq 'legacy' -and $QtMajor -ne 4) { throw 'Only Qt4 has the API4 legacy recipe' }
$phases=if ($mode -eq 'examples') { @('examples','package') } else { @($mode) }
foreach ($phase in $phases) {
    $phaseOptions=@{}+$options
    if ($phase -eq 'legacy') { $phaseOptions.Remove('Mode') | Out-Null }
    else { $phaseOptions.Mode=$phase }
    if ($phase -eq 'package') {
        foreach ($key in @('ParallelJobs','SdkImage')) { $phaseOptions.Remove($key) | Out-Null }
    }
    $global:LASTEXITCODE=0
    & "$PSScriptRoot/qt${QtMajor}-android.ps1" @phaseOptions
    $completed=$?
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    if (!$completed) { exit 1 }
}
