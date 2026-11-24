# SPDX-License-Identifier: GPL-3.0-or-later
$ErrorActionPreference='Stop'
. "$PSScriptRoot/../../run/android/android-api21-log.ps1"
$marker='BEGIN-0123456789abcdef0123456789abcdef'
$boundary="I/LongreachCase( 3524): $marker"
$old='F/libc    ( 3479): Fatal signal 11 (SIGSEGV), code 1 in tid 3489 (Binder_2)'
$current='I/ActivityManager( 1504): Start proc org.longreachqt.examples.quickqmlgallery: pid=3536'
$progress='I/libquick-qml-gallery_x86_64.so( 3536): PASS: qml/jsengine-eval'
$raw=@($old, '', $boundary, $current, $progress)
$scoped=@(Get-AndroidApi21CaseLog -RawLog $raw -Marker $marker)
if ($scoped.Count -ne 2 -or $scoped[0] -ne $current -or $scoped[1] -ne $progress) {
    throw 'Installation crash was not separated from the current application'
}
# A native/Java failure after the boundary must remain visible to all existing
# fatal checks, including failures in system services during the actual case.
foreach ($failure in @('F/libc ( 3536): Fatal signal 11',
        'E/AndroidRuntime( 3536): FATAL EXCEPTION: main',
        'E/art ( 3536): VM aborting', 'F/libc ( 1504): Fatal signal 6')) {
    $result=@(Get-AndroidApi21CaseLog -RawLog ($raw + $failure) -Marker $marker)
    if ($result[-1] -ne $failure) { throw 'Current-case fatal record was lost' }
}
foreach ($invalid in @(@($old,$current), @($boundary,$boundary,$progress))) {
    $rejected=$false
    try { Get-AndroidApi21CaseLog -RawLog $invalid -Marker $marker | Out-Null }
    catch { $rejected=$true }
    if (!$rejected) { throw 'Missing or ambiguous launch boundary was accepted' }
}
$rejected=$false
try { Get-AndroidApi21CaseLog -RawLog $raw -Marker 'invalid' | Out-Null }
catch { $rejected=$true }
if (!$rejected) { throw 'Malformed launch marker was accepted' }
Write-Output 'PASS: API21 launch log boundary, retained current fatal records, missing/duplicate marker rejection'
