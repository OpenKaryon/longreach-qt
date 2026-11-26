# SPDX-License-Identifier: GPL-3.0-or-later
# Real shared observer and Python validators; only ADB/native boundaries recorded.
param([string]$RepoRoot=(Resolve-Path "$PSScriptRoot/../../..").Path)
$ErrorActionPreference='Stop'
. "$RepoRoot/scripts/run/android/android-process-exit.ps1"
. "$RepoRoot/scripts/run/android/android-extras.ps1"
$parent=(New-Item -ItemType Directory -Force "$RepoRoot/build/fixtures").FullName
$fixture=(New-Item -ItemType Directory (Join-Path $parent ('android-extras-'+[guid]::NewGuid().ToString('N')))).FullName
function Assert-Extras([bool]$Value,[string]$Message) { if (!$Value) { throw $Message } }
function Write-ExtrasQuery([string]$Directory,[string]$Name,[string]$Value) {
    [IO.File]::WriteAllText("$Directory/$Name.stdout",$Value,[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText("$Directory/$Name.stderr",'',[Text.UTF8Encoding]::new($false))
    if ($Value) { return @(Get-Content -LiteralPath "$Directory/$Name.stdout") }
}
function Invoke-AndroidExitQuery {
    param($Adb,$Serial,[string[]]$Command,[string]$Directory,[string]$Name,$TimeoutMilliseconds,[switch]$AllowNonzero)
    $context=$global:ExtrasBoundary
    $context.Calls.Add($Name)
    $value=''
    if ($Name -match '^extras-([01])-(live|exit)-request$') {
        $index=[int]$Matches[1];$phase=$Matches[2];$number=3010+$index
        if ($index -eq 1) { Assert-Extras ($context.Stage[0] -eq 2) 'Second service requested before the first host exit ACK' }
        if ($phase -eq 'exit') {
            Assert-Extras ($context.Stage[$index] -eq 1) 'Service exit requested before its live host ACK'
            if ($context.Mode -eq 'wrong-finish') { $number++ }
        }
        if ($context.Mode -eq 'pending' -and $index -eq 0 -and !$context.PendingSeen.Contains($phase)) {
            $context.PendingSeen.Add($phase) | Out-Null
            $remote="/data/data/$($context.Package)/files/extras-service-$index-$phase.txt"
            Assert-Extras ($Command.Count -eq 3 -and $Command[0] -ceq 'shell' -and $Command[1] -ceq 'cat' -and $Command[2] -ceq $remote) 'Pending query changed its exact rendezvous path'
            $value="$remote`: No such file or directory`r`r`n"
            return Write-ExtrasQuery $Directory $Name $value
        }
        $value="$number $($context.Nonces[$index])`n"
        if ($context.Mode -eq 'malformed') { $value='malformed live receipt' }
        if ($context.Mode -eq 'other-missing') { $value='/data/data/another/file: No such file or directory' }
        if ($context.Mode -eq 'permission') { $value="/data/data/$($context.Package)/files/extras-service-$index-$phase.txt`: Permission denied" }
        if ($context.Mode -eq 'transport') { throw 'Recorded transport failure' }

    } elseif ($Name -match '^extras-([01])-live-stat-([ab])$') {
        $index=[int]$Matches[1];$part=$Matches[2];$number=3010+$index;$ticks=800+$index
        if ($context.Mode -eq 'birth' -and $part -eq 'b') { $ticks++ }
        $value="$number (app_process) S 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 $ticks 0 0`n"
    } elseif ($Name -match '^extras-([01])-live-cmdline$') {
        $value=$context.Package+':longreach_extras'+[char]0
        if ($context.Mode -eq 'command') { $value=$context.Package+[char]0 }
    } elseif ($Name -match '^extras-([01])-(live|exit)-ack-push$') {
        $index=[int]$Matches[1];$phase=$Matches[2]
        Assert-Extras ($Command[0] -ceq 'push') 'Observer did not use a bounded ACK push'
        Assert-Extras ((Get-Content -LiteralPath $Command[1] -Raw).Trim() -ceq $context.Nonces[$index]) 'Observer acknowledged another service nonce'
        Assert-Extras (Test-Path -LiteralPath "$Directory/extras-$index-$phase.json") 'ACK preceded its validated host receipt'
        if ($context.Mode -eq 'push-failure') { throw 'Recorded ACK transport failure' }
        $context.Stage[$index]=$(if ($phase -eq 'live') { 1 } else { 2 })
        $value='1 file pushed'
    } elseif ($Name -match '^extras-([01])-exit-ps-[01]$') {
        $value="USER PID PPID NAME`nroot 1 0 /init`nu0a20 1234 1 $($context.Package)`n"
    } elseif ($Name -ne 'extras-round1-marker') { throw "Unexpected observer transport: $Name" }
    Write-ExtrasQuery $Directory $Name $value
}
function Get-AndroidCaseRawLog {
    param($Adb,$Serial,[string]$Directory,[string]$Name,$TimeoutMilliseconds)
    Assert-Extras ($Name -match '^extras-([01])-exit-log-[01]$') 'Unexpected raw service log query'
    $index=[int]$Matches[1];$number=3010+$index;$context=$global:ExtrasBoundary
    $marker=if ($index -eq 0) { $context.Marker } else { (Get-Content "$Directory/extras-round1-marker.txt" -Raw).Trim() }
    $service=$context.Package+':longreach_extras'
    $value="I/LongreachCase( 77): $marker`nI/ActivityManager( 100): Start proc ${number}:$service/u0a20 for service`nI/ActivityManager( 100): Process $service (pid $number) has died.`n"
    if ($context.Mode -eq 'late-crash') { $value+="I/DEBUG( 99): *** *** ***`n" }
    Write-ExtrasQuery $Directory $Name $value
}
try {
    foreach ($mode in 'ok','pending','malformed','other-missing','permission','transport','birth','command','wrong-finish','late-crash','push-failure') {
        $directory=(New-Item -ItemType Directory -Path "$fixture/$mode").FullName
        $global:ExtrasBoundary=@{Mode=$mode;Package='org.longreachqt.examples.qtselftest';Marker=('BEGIN-'+('f'*32));
            Nonces=@(('c'*32),('d'*32));Stage=@(0,0);PendingSeen=[Collections.Generic.HashSet[string]]::new();Calls=[Collections.Generic.List[string]]::new()}
        $failed=$false
        try {
            foreach ($step in 0..5) {
                Observe-AndroidExtrasServices -Adb 'recorded-adb' -Serial 'emulator-5582' -Directory $directory `
                    -Package $global:ExtrasBoundary.Package -Marker $global:ExtrasBoundary.Marker
            }
        } catch { if ($mode -in @('ok','pending')) { throw }; $failed=$true }
        if ($mode -in @('ok','pending')) {
            Assert-Extras (!$failed -and $global:ExtrasBoundary.Stage[0] -eq 2 -and $global:ExtrasBoundary.Stage[1] -eq 2) 'Both host-observed service exits did not complete'
            Assert-Extras (Test-Path -LiteralPath "$directory/extras-services.json") 'Missing sealed host service record'
            $seal=Get-Content "$directory/extras-services.json" -Raw | ConvertFrom-Json
            Assert-Extras ($seal.rounds.Count -eq 2 -and !$seal.qualification) 'Observer claimed full qualification'
            $before=Get-FileHash "$directory/extras-services.json"
            Observe-AndroidExtrasServices -Adb 'recorded-adb' -Serial 'emulator-5582' -Directory $directory `
                -Package $global:ExtrasBoundary.Package -Marker $global:ExtrasBoundary.Marker
            Assert-Extras ($before.Hash -ceq (Get-FileHash "$directory/extras-services.json").Hash) 'Completed observer changed its sealed history'
            if ($mode -eq 'pending') { Assert-Extras ($global:ExtrasBoundary.PendingSeen.Count -eq 2) 'Both pending live and exit rendezvous were not exercised' }
        } else {
            Assert-Extras $failed "Observer accepted recorded failure: $mode"
            Assert-Extras (!(Test-Path -LiteralPath "$directory/extras-services.json")) 'Failed observer published sealed service success'
            Assert-Extras ($global:ExtrasBoundary.Stage[0] -lt 2) 'Failed service exit was acknowledged'
        }
    }
    'PASS: shared AndroidExtras observer, two live/exit barriers, pending live/exit files and nine retained refusals (recorded boundaries only)'
} finally {
    $resolved=[IO.Path]::GetFullPath($fixture)
    if ([IO.Path]::GetDirectoryName($resolved) -cne [IO.Path]::GetFullPath($parent) -or
            ![IO.Path]::GetFileName($resolved).StartsWith('android-extras-',[StringComparison]::Ordinal)) { throw 'Unexpected fixture cleanup target' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
