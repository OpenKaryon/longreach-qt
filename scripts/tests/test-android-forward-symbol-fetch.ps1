# SPDX-License-Identifier: GPL-3.0-or-later
# Ordinary recording fixture for the actual fetch entry point; no downloads.
param([string] $RepoRoot = (Resolve-Path "$PSScriptRoot/../..").Path)
$ErrorActionPreference = 'Stop'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('longreach-forward-fetch-' + [guid]::NewGuid().ToString('N'))
$global:ForwardFetchCalls = [Collections.Generic.List[object]]::new()
$global:ForwardFetchFail = $false
function python {
    param([Parameter(ValueFromRemainingArguments)][string[]] $Arguments)
    $global:ForwardFetchCalls.Add(@($Arguments))
    $global:LASTEXITCODE = if ($global:ForwardFetchFail) { 7 } else { 0 }
}
function Assert-ForwardFetch($Condition, [string] $Message) {
    if (!$Condition) { throw $Message }
}
try {
    New-Item -ItemType Directory -Path "$fixture/scripts/fetch/locks" -Force | Out-Null
    Copy-Item -LiteralPath "$RepoRoot/scripts/fetch/qt5-android.ps1" -Destination "$fixture/scripts/fetch/qt5-android.ps1"
    Copy-Item -LiteralPath "$RepoRoot/scripts/fetch/locks/qt6-android-api21-inputs.json" -Destination "$fixture/scripts/fetch/locks/qt6-android-api21-inputs.json"
    [IO.File]::WriteAllText("$fixture/scripts/fetch/locks/qt5-android-api10-inputs.json",'{"sources":[],"shared_sources":[]}')
    @'
param($Abi,$Scope,[switch]$PlatformOnly,$AndroidSdk)
$global:ForwardFetchDelegated = "$Abi|$Scope|$PlatformOnly"
'@ | Set-Content -LiteralPath "$fixture/scripts/fetch/qt6-android.ps1"
    $lock = Get-Content -LiteralPath "$RepoRoot/scripts/fetch/locks/qt6-android-api21-inputs.json" -Raw | ConvertFrom-Json
    $pin = @($lock.sources | Where-Object { $_.file -ceq 'android-ndk-r27-linux.zip' })[0]
    foreach ($abi in @('armeabi-v7a','x86')) {
        foreach ($scope in @('sdk','all','test')) {
            $global:ForwardFetchCalls.Clear()
            & "$fixture/scripts/fetch/qt5-android.ps1" -Abi $abi -Scope $scope | Out-Null
            $expected = if ($scope -eq 'test') { 0 } else { 1 }
            Assert-ForwardFetch ($global:ForwardFetchCalls.Count -eq $expected) "Wrong forward-input fetch count: $abi/$scope"
            if ($expected) {
                $call = $global:ForwardFetchCalls[0]
                Assert-ForwardFetch ($call.Count -eq 4 -and [IO.Path]::GetFullPath($call[0]) -eq [IO.Path]::GetFullPath("$fixture/scripts/fetch/fetch.py")) 'Did not use shared pinned fetch boundary'
                Assert-ForwardFetch ($call[1] -ceq $pin.url -and $call[3] -ceq $pin.sha256) 'Forward input lost lock URL/hash'
                Assert-ForwardFetch ([IO.Path]::GetFullPath($call[2]) -eq [IO.Path]::GetFullPath("$fixture/downloads/android-lollipop/android-ndk-r27-linux.zip")) 'Forward input no longer matches Docker mount'
            }
        }
    }
    foreach ($abi in @('arm64-v8a','x86_64')) {
        $global:ForwardFetchCalls.Clear()
        $global:ForwardFetchDelegated=''
        & "$fixture/scripts/fetch/qt5-android.ps1" -Abi $abi -Scope sdk | Out-Null
        Assert-ForwardFetch ($global:ForwardFetchCalls.Count -eq 0) 'API21 duplicated the forward-input fetch'
        Assert-ForwardFetch ($global:ForwardFetchDelegated -ceq "$abi|sdk|True") 'API21 stopped using existing platform-only fetch'
    }
    $global:ForwardFetchFail=$true
    $failed=$false
    try { & "$fixture/scripts/fetch/qt5-android.ps1" -Abi x86 -Scope sdk | Out-Null }
    catch { if ($_.Exception.Message -notmatch 'Could not fetch the API21 forward-symbol') { throw }; $failed=$true }
    Assert-ForwardFetch $failed 'Forward-input fetch failure was ignored'
    Write-Output 'Forward-symbol fetch recording passed: six API10 routes, two API21 routes and failure propagation; downloads=0.'
} finally {
    $resolved = [IO.Path]::GetFullPath($fixture)
    $temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    if ($resolved.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'longreach-forward-fetch-*') {
        if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
    } else { throw 'Unexpected fixture cleanup path' }
    Remove-Variable ForwardFetchCalls,ForwardFetchFail,ForwardFetchDelegated -Scope Global -ErrorAction SilentlyContinue
}
