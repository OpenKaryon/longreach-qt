# SPDX-License-Identifier: GPL-3.0-or-later
#Requires -Version 7.0
param(
    [Parameter(Mandatory)][string]$ArtifactRoot,
    [ValidateSet('armeabi-v7a','x86')][string]$Abi='x86',
    [Parameter(Mandatory)][string]$SystemDirectory,
    [Parameter(Mandatory)][string]$Emulator,
    [Parameter(Mandatory)][string]$Kernel,
    [Parameter(Mandatory)][string]$Ramdisk,
    [string]$AndroidSdk=$env:ANDROID_HOME,
    [ValidatePattern('^[a-z0-9][a-z0-9-]{0,63}$')][string]$RunName=('sound-cache-20-'+[guid]::NewGuid().ToString('N')),
    [switch]$ClassicEmulator
)
$ErrorActionPreference='Stop'
$Abi=$Abi.ToLowerInvariant()
$repo=(Resolve-Path "$PSScriptRoot/../..").Path
. "$repo/scripts/build/android-api21/artifact-lock.ps1"
. "$PSScriptRoot/android/android-adb-endpoint.ps1"
if (!$AndroidSdk) { throw 'Set ANDROID_HOME or pass -AndroidSdk' }
$root=(Resolve-Path -LiteralPath $ArtifactRoot).Path
$SystemDirectory=(Resolve-Path -LiteralPath $SystemDirectory).Path
$AndroidSdk=(Resolve-Path -LiteralPath $AndroidSdk).Path
foreach ($name in @('Emulator','Kernel','Ramdisk')) {
    Set-Variable -Name $name -Value (Get-Item -LiteralPath (Get-Variable -Name $name -ValueOnly)).FullName
}
foreach ($path in @($root,(Join-Path $root 'diagnostics'))) {
    if (Test-Path -LiteralPath $path) {
        $item=Get-Item -LiteralPath $path -Force
        if (!$item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Sound series root/diagnostics must be ordinary directories'
        }
    }
}
$directory=Join-Path (Join-Path $root 'diagnostics') $RunName
$endpoint=Get-AndroidAdbEndpoint
$workingDirectory=(Get-Location).ProviderPath
$rootLock=Enter-AndroidArtifactLock $root
$started=$false
$index=0
$phase='begin'
function Invoke-SoundSeriesTool([string[]]$Arguments) {
    & python "$PSScriptRoot/android/android-sound-cache-series.py" @Arguments
    if ($LASTEXITCODE) { throw "Sound series metadata $($Arguments[0]) failed" }
}
try {
    $begin=@('begin','--root',$root,'--directory',$directory,'--abi',$Abi,
        '--emulator',$Emulator,'--system-directory',$SystemDirectory,'--kernel',$Kernel,
        '--ramdisk',$Ramdisk,'--android-sdk',$AndroidSdk,'--adb-port',[string]$endpoint.port,
        '--working-directory',$workingDirectory,
        '--artifact-lease-held')
    if ($ClassicEmulator) { $begin+='--classic-emulator' }
    Invoke-SoundSeriesTool $begin | Out-Null
    $started=$true
    $inputs=Get-Content -LiteralPath "$directory/series-inputs.json" -Raw | ConvertFrom-Json
    for ($index=1; $index -le 20; $index++) {
        $phase='checkpoint'
        if ((Get-Location).ProviderPath -cne $workingDirectory) {
            throw 'Sound series frontend working directory changed before its next attempt'
        }
        $currentEndpoint=Get-AndroidAdbEndpoint
        if ($currentEndpoint.port -ne $endpoint.port -or $currentEndpoint.socket -cne $endpoint.socket) {
            throw 'Sound series ADB endpoint changed before its next attempt'
        }
        Invoke-SoundSeriesTool @('checkpoint','--directory',$directory,'--index',[string]$index,'--artifact-lease-held') | Out-Null
        $phase='guest'
        $case=Join-Path $directory ('run-{0:d2}' -f $index)
        Write-Host "Sound-cache diagnostic attempt $index/20"
        & "$PSScriptRoot/qt5-android-gingerbread.ps1" -Abi $Abi -Apk "$root/apk/extended/qt-selftest.apk" `
            -SystemDirectory $SystemDirectory -Emulator $Emulator -Kernel $Kernel -Ramdisk $Ramdisk `
            -OutputDirectory $case -AndroidSdk $AndroidSdk -Package org.longreachqt.examples.qtselftest `
            -ApplicationArguments '--sound-cache-teardown' -ArtifactRoot $root -SdkImageId $inputs.sdk_image_id `
            -ClassicEmulator:$ClassicEmulator -RasterImageDepth 32 -QtQuickBackend software | Out-Null
        $phase='record'
        Invoke-SoundSeriesTool @('record','--directory',$directory,'--index',[string]$index,'--artifact-lease-held') | Out-Null
    }
    $phase='finish'
    Invoke-SoundSeriesTool @('finish','--directory',$directory,'--artifact-lease-held') | Out-Null
    $phase='verify'
    Invoke-SoundSeriesTool @('verify','--directory',$directory,'--artifact-lease-held') | Out-Null
    Write-Output "Sound-cache diagnostic: 20 attempts passed the recorded termination checks; qualification=false; $directory/series-result.json"
} catch {
    $seriesError=$_
    if ($started) {
        try {
            Invoke-SoundSeriesTool @('fail','--directory',$directory,'--index',[string][Math]::Min($index,20),
                '--phase',$phase,'--message',$seriesError.Exception.Message,'--artifact-lease-held') | Out-Null
        } catch { Write-Verbose "Could not save additional series failure record: $_" }
    }
    throw $seriesError
} finally {
    if ($rootLock) { $rootLock.Dispose() }
}
