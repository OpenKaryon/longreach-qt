# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
<# Actual API4 SDK dispatcher with recorded Docker/source boundaries; no build or guest executes. #>
param([string]$RepoRoot=(Resolve-Path "$PSScriptRoot/../../..").Path)
$ErrorActionPreference='Stop'
$parent=(New-Item -ItemType Directory -Force "$RepoRoot/build/fixtures").FullName
$fixture=Join-Path $parent ('api4-sdk-modes-'+[guid]::NewGuid().ToString('N'))
$state=@{Calls=[Collections.Generic.List[object]]::new();Busy=$false;Changed=$false;Wrong=$false;Root='';Secret='';SourceBytes='';RejectNative=$false;ClientBusy=$false}
function Assert-Api4Sdk([bool]$Value,[string]$Message) { if (!$Value) { throw $Message } }
function Get-Process { param($Name,$ErrorAction) if ($state.Busy) { [pscustomobject]@{Name='emulator-arm'} } }
function python {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    $state.Calls.Add(@('python')+$Arguments)
    $global:LASTEXITCODE=0
    if ($Arguments[1] -eq 'check-native' -and $state.RejectNative) { $global:LASTEXITCODE=9; return }
    if ($Arguments[1] -eq 'capture-source') {
        $path=$Arguments[[Array]::IndexOf($Arguments,'--snapshot')+1]
        [IO.File]::WriteAllText($path,'{"inputs":{"fixture":"source bytes"},"git_head":"recording fixture"}')
        $state.SourceBytes=[IO.File]::ReadAllText($path)
    } elseif ($Arguments[1] -eq 'compare-source' -and $state.Changed) { $global:LASTEXITCODE=7 }
}
function docker {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    $state.Calls.Add(@('docker')+$Arguments)
    $global:LASTEXITCODE=0
    switch ($Arguments[0]) {
        'build' {
            $secret=$Arguments[[Array]::IndexOf($Arguments,'--secret')+1]
            $state.Secret=($secret -replace '^id=longreach-jobs,src=','')
            Assert-Api4Sdk ([IO.File]::ReadAllText($state.Secret).Trim() -eq '3') 'SDK jobs were not forwarded through the normal secret'
        }
        'image' {
            if ($Arguments -contains '{{.Id}}') { 'sha256:'+('a'*64); return }
            @{Id=('sha256:'+('a'*64));Os='linux';Architecture='amd64';Config=@{Labels=@{
                'org.openkaryon.longreach-qt.version'='4.8.7';
                'org.openkaryon.longreach-qt.compiler'='LLVM 21.1.8';
                'org.openkaryon.longreach-qt.platform'='android-donut-armeabi';
                'org.openkaryon.longreach-qt.android-api'=$(if($state.Wrong){'21'}else{'4'})
            }}} | ConvertTo-Json -Depth 5 -Compress
        }
        'ps' { if ($state.ClientBusy) { ('c'*64)+' recorded-api4-client' } }
        'create' { 'b'*64 }
        'cp' {
            if ($Arguments[1] -like '*/api4-sdk.json') {
                @{api=4;abi='armeabi';qt='4.8.7';runtime_linkage='static'} | ConvertTo-Json | Set-Content $Arguments[2]
            } else { 'recorded qmake query' | Set-Content $Arguments[2] }
        }
    }
}
function Invoke-Api4Sdk([string]$Name,[hashtable]$Extra=@{}) {
    $state.Root=Join-Path $fixture $Name
    $options=@{Abi='armeabi';Mode='sdk';OutputDirectory=$state.Root;InputDirectory="$fixture/custom archives";ParallelJobs=3}
    foreach ($key in $Extra.Keys) { $options[$key]=$Extra[$key] }
    & "$fixture/repo/scripts/build/qt4-android.ps1" @options | Out-Null
}
function Fail-Api4Sdk([string]$Name,[string]$Reason,[hashtable]$Extra=@{}) {
    try { Invoke-Api4Sdk $Name $Extra } catch {
        Assert-Api4Sdk ($_.Exception.Message -match $Reason) "Unexpected SDK failure: $_"
        return
    }
    throw 'SDK fixture expected a failure'
}
try {
    New-Item -ItemType Directory -Force "$fixture/repo/scripts/build/qt4-android","$fixture/custom archives" | Out-Null
    foreach ($directory in @('scripts/run/android','scripts/build/android-api21','scripts/build/qt4-android')) {
        $target=Join-Path "$fixture/repo" $directory
        New-Item -ItemType Directory -Force $target | Out-Null
        Copy-Item "$RepoRoot/$directory/*" $target -Recurse -Force
    }
    Copy-Item "$RepoRoot/scripts/build/qt4-android.ps1" "$fixture/repo/scripts/build/qt4-android.ps1"
    Invoke-Api4Sdk 'fresh'
    $build=@($state.Calls | Where-Object { $_[0] -eq 'docker' -and $_[1] -eq 'build' })[0]
    Assert-Api4Sdk ($build -contains 'api4-sdk') 'SDK mode selected a legacy/tools stage'
    Assert-Api4Sdk ($build -contains ("android-api4-inputs="+(Resolve-Path "$fixture/custom archives").Path)) 'Custom archive directory did not reach its named context'
    Assert-Api4Sdk ($build -contains 'longreach-qt4-android-donut-armeabi:llvm21') 'SDK overwrote the shared bootstrap tools tag'
    Assert-Api4Sdk (!$build.Contains('ANDROID_ABI=armeabi')) 'Fixed API4 stage changed generic ABI-selected stages'
    Assert-Api4Sdk (!(Test-Path -LiteralPath $state.Secret)) 'SDK jobs secret was not closed'
    Assert-Api4Sdk (!(Test-Path "$($state.Root)/api4-sdk-in-progress.json")) 'Successful SDK retained a pending marker'
    $generation=Get-Content "$($state.Root)/sdk-generation.json" -Raw | ConvertFrom-Json
    Assert-Api4Sdk ($generation.sdk_image_id -eq ('sha256:'+('a'*64)) -and $generation.guest_qualification -eq $false) 'SDK identity or qualification scope changed'
    $calls=$state.Calls.Count
    Fail-Api4Sdk 'fresh' 'fresh output directory'
    Assert-Api4Sdk ($state.Calls.Count -eq $calls) 'Completed generation was rebuilt/overwritten'

    $state.Changed=$true
    Fail-Api4Sdk 'changed' 'exited with code 7'
    Assert-Api4Sdk (!(Test-Path "$($state.Root)/sdk-image-id.txt")) 'Changed source was published as complete'
    Assert-Api4Sdk ((Get-Content "$($state.Root)/api4-sdk-in-progress.json" -Raw | ConvertFrom-Json).status -eq 'failed') 'Failure was not preserved'
    Assert-Api4Sdk ([IO.File]::ReadAllText("$($state.Root)/sdk-source-inputs.json") -eq $state.SourceBytes) 'Failed source snapshot was replaced'
    $state.Changed=$false
    $state.Wrong=$true
    Fail-Api4Sdk 'wrong-image' 'not the installed Qt4 API4'
    Assert-Api4Sdk (!(Test-Path "$($state.Root)/sdk-image-id.txt")) 'Wrong image labels were published'
    $state.Wrong=$false
    $state.Busy=$true
    $calls=$state.Calls.Count
    Fail-Api4Sdk 'busy' 'Stop the Android emulator'
    Assert-Api4Sdk ($state.Calls.Count -eq $calls) 'Busy guest reached a build/source boundary'
    $state.Busy=$false
    Fail-Api4Sdk 'reserved' 'bootstrap' @{SdkImage='longreach-qt4-android-donut:llvm21'}
    # These boundaries are replaced only inside the owned fixture. The real
    # dispatcher runs; no packaging tools, compiler or Android guest execute.
    $hostFile="$fixture/repo/scripts/build/qt4-android/host.ps1"
    Add-Content -LiteralPath $hostFile -Value @'
function Expand-DonutInput { param($Archive,$Hash,$Destination,$Member) return "$Destination/android.jar" }
function Get-AndroidPackagingJava { return @{javac='/recorded-java/javac.exe';launcher='/recorded-java/java.exe'} }
function Initialize-DonutSigningKey { param($OutputDirectory,$JavaDirectory) return "$OutputDirectory/local-probe.jks" }
'@
    Set-Content -LiteralPath "$fixture/repo/scripts/build/qt4-android/package.ps1" -Value @'
param($Profile,$NativeDirectory,$OutputDirectory,$AndroidSdk,$AndroidJar,$JavaTools)
$state.Calls.Add(@('package',$Profile))
'@
    Set-Content -LiteralPath "$fixture/repo/scripts/run/qt4-android-donut.ps1" -Value @'
param($InputDirectory,$OutputDirectory,$AndroidSdk,$Profiles)
$state.Calls.Add(@('runner')+@($Profiles))
'@
    New-Item -ItemType Directory -Path "$fixture/recorded-sdk" | Out-Null
    function Invoke-Api4ClientMode([string]$Mode,[hashtable]$Extra=@{}) {
        $options=@{Abi='armeabi';Mode=$Mode;OutputDirectory="$fixture/fresh";
            InputDirectory="$fixture/custom archives";AndroidSdk="$fixture/recorded-sdk"}
        foreach ($key in $Extra.Keys) { $options[$key]=$Extra[$key] }
        & "$fixture/repo/scripts/build/qt4-android.ps1" @options | Out-Null
    }
    $before=$state.Calls.Count
    Invoke-Api4ClientMode 'examples'
    $calls=@($state.Calls | Select-Object -Skip $before)
    $compile=@($calls | Where-Object { $_[0] -eq 'docker' -and $_[1] -eq 'run' })
    Assert-Api4Sdk ($compile.Count -eq 1 -and $compile[0] -contains '/repo/scripts/build/qt4-android/build-api4-examples.sh') 'Examples did not use installed-SDK clients'
    Assert-Api4Sdk ($compile[0] -contains ('sha256:'+('a'*64))) 'Examples used a mutable image tag'
    Assert-Api4Sdk (@($calls | Where-Object { $_[0] -eq 'docker' -and $_[1] -eq 'build' }).Count -eq 0) 'Examples rebuilt the native producer'
    $begin=@($calls | Where-Object { $_[0] -eq 'python' -and $_[2] -eq 'begin' })
    Assert-Api4Sdk ($begin.Count -eq 1 -and $begin[0] -contains '--sdk-image-id') 'Native reservation missed its SDK binding'
    Assert-Api4Sdk ($compile[0] -contains '--name') 'Example container has no stable owned slot'
    $state.ClientBusy=$true
    $before=$state.Calls.Count
    try { Invoke-Api4ClientMode 'examples'; throw 'Expected a busy client slot to fail' } catch {
        Assert-Api4Sdk ($_.Exception.Message -match 'client cache is busy|container slot is still present') "Unexpected busy-slot failure: $_"
    }
    $calls=@($state.Calls | Select-Object -Skip $before)
    Assert-Api4Sdk (@($calls | Where-Object { $_[0] -eq 'python' }).Count -eq 0) 'Busy client reserved a new generation'
    $state.ClientBusy=$false
    Invoke-Api4ClientMode 'package'
    $packages=@($state.Calls | Where-Object { $_[0] -eq 'package' } | ForEach-Object { $_[1] })
    Assert-Api4Sdk (($packages -join ',') -ceq 'bootstrap,strict,core,quick,selftest,graphics,network,painting') 'Package mode did not include exactly eight profiles'
    Invoke-Api4ClientMode 'test' @{Profiles=@('core','quick')}
    $runners=@($state.Calls | Where-Object { $_[0] -eq 'runner' })
    Assert-Api4Sdk ($runners.Count -eq 1 -and ($runners[0] -join ',') -ceq 'runner,core,quick') 'Test selection did not reach the existing diagnostic runner'
    $state.RejectNative=$true
    foreach ($mode in 'package','test') {
        $before=$state.Calls.Count
        try { Invoke-Api4ClientMode $mode; throw 'Expected the stale-native boundary to fail' } catch {
            Assert-Api4Sdk ($_.Exception.Message -match 'exited with code 9') "Unexpected stale native failure: $_"
        }
        $calls=@($state.Calls | Select-Object -Skip $before)
        Assert-Api4Sdk (@($calls | Where-Object { $_[0] -in 'package','runner' }).Count -eq 0) 'Stale clients reached packaging or guest boundaries'
        Assert-Api4Sdk ($calls[0] -contains '--installed-sdk') 'Explicit phase accepted a legacy combined generation'
    }
    Write-Output 'PASS: API4 SDK/examples/package/test routing, immutable SDK binding and retained failure gates (recorded boundaries only)'

} finally {
    $resolved=[IO.Path]::GetFullPath($fixture)
    $boundary=[IO.Path]::GetFullPath($parent)+[IO.Path]::DirectorySeparatorChar
    if (!$resolved.StartsWith($boundary,[StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture cleanup escaped its owned parent' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
    $global:LASTEXITCODE=0
}
