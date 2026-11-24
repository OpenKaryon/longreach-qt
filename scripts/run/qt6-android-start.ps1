# SPDX-License-Identifier: GPL-3.0-or-later
param([ValidateSet('armeabi-v7a','arm64-v8a','x86','x86_64')][string]$Abi = 'armeabi-v7a', [Parameter(Mandatory)][string]$OutputDirectory, [Parameter(Mandatory)][string]$Emulator,
      [string]$RunName='sdk-suite', [ValidateSet('on','mesa')][string]$Gpu='on',[switch]$PassThru)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/android-emulator-state.ps1"
. "$PSScriptRoot/android-owned-process.ps1"
. "$PSScriptRoot/../build/android-api21/artifact-lock.ps1"
$Gpu=$Gpu.ToLowerInvariant()
$root=(Resolve-Path -LiteralPath $OutputDirectory).Path
$media="$root/media/$Abi"
# ARM64's kernel-qemu is ranchu; the Intel archives name it explicitly.
$kernel = if ($Abi -in @('x86','x86_64')) { 'kernel-ranchu' } else { 'kernel-qemu' }
if ($RunName -notmatch '^[a-z0-9-]+$') { throw 'Invalid run directory name' }
$run = "$root/$RunName"
Assert-AndroidOwnedArtifactRootAvailable $root
$startupLease=Enter-AndroidArtifactLock $root
try {
Clear-AndroidResultAggregates $root
Assert-AndroidNoEmulatorRunning -Emulator $Emulator -Message 'Another emulator is running'
# A frozen cache does not execute build jobs; it stays paused during regression runs.
$running = & docker ps --filter status=running --filter label=org.openkaryon.longreach-qt.android-api=21 --format '{{.Names}}'
if ($LASTEXITCODE) { throw 'Cannot verify that the build slot is free' }
if ($running) { throw 'Stop the build container before starting the emulator' }
if (Test-Path -LiteralPath $run) { throw 'Archive the previous emulator run explicitly before starting a fresh one' }
New-Item -ItemType Directory -Path $run | Out-Null
Copy-Item -LiteralPath "$media/userdata.img" -Destination "$run/userdata-qemu.img"
# The pinned Intel emulator uses host-side software GLES for both legacy GPU modes.
$gpuMode = if ($Abi -in @('x86','x86_64')) { 'swiftshader_indirect' } else { $Gpu }
$arguments = @('-sysdir',$media,'-datadir',$run,'-system',"$media/system.img",'-kernel',"$media/$kernel",'-ramdisk',"$media/ramdisk.img",'-data',"$run/userdata-qemu.img",'-initdata',"$media/userdata.img",'-no-window','-no-audio','-no-snapshot','-no-snapstorage','-skin','480x800','-partition-size','1024','-memory','1024','-gpu',$gpuMode,'-port','5582','-no-boot-anim','-verbose','-show-kernel')
if ($Abi -eq 'armeabi-v7a') {
    $arguments += @('-qemu','-cpu','cortex-a8')
} else {
    # The QEMU2 frontend needs an AVD to choose the target machine. Keep all
    # configuration and writable guest data within this unique run directory.
    $sdkRoot = Split-Path (Split-Path -Parent $Emulator) -Parent
    $relativeMedia = [IO.Path]::GetRelativePath($sdkRoot, $media).Replace('\','/')
    $avdHome = "$run/avd"
    $avdName = "longreach-api21-$Abi"
    $cpuArch = switch ($Abi) { 'x86' { 'x86' }; 'x86_64' { 'x86_64' }; default { 'arm64' } }
    $cpuModel = switch ($Abi) { 'x86' { 'Conroe' }; 'x86_64' { 'Nehalem' }; default { 'cortex-a57' } }
    # The archived 32-bit kernel panicked during a normal two-core TCG boot.
    # Keep this legacy guest single-core; native threads remain enabled.
    $guestCores = if ($Abi -eq 'x86') { 1 } else { 2 }
    $avdPath = "$avdHome/$avdName.avd"
    New-Item -ItemType Directory -Path $avdPath -Force | Out-Null
    @('avd.ini.encoding=UTF-8', "path=$avdPath", 'target=android-21') |
        Set-Content -LiteralPath "$avdHome/$avdName.ini" -Encoding ascii
    @('avd.ini.encoding=UTF-8',"abi.type=$Abi","hw.cpu.arch=$cpuArch",
      "hw.cpu.model=$cpuModel","hw.cpu.ncore=$guestCores",'hw.audioInput=no','hw.audioOutput=no','hw.ramSize=1024','hw.lcd.width=480',
      'hw.lcd.height=800','hw.lcd.density=160','hw.keyboard=yes',
      'hw.gpu.enabled=yes',"image.sysdir.1=$relativeMedia",'tag.id=default',
      'tag.display=Default','target=android-21') |
        Set-Content -LiteralPath "$avdPath/config.ini" -Encoding ascii
    $engineOptions = @('-avd',$avdName,'-engine','qemu2','-accel','off')
    if ($Abi -in @('x86','x86_64')) {
        $engineOptions += @('-feature','-Vulkan','-feature','-QuickbootFileBacked')
    }
    $arguments = $engineOptions + @('-shell-serial',"file:$run/kernel-shell.log") + @($arguments | Where-Object { $_ -ne '-no-audio' })
}
if ($Abi -in @('x86','x86_64')) { $arguments += @('-qemu','-cpu',$cpuModel) }
# Save the unquoted argv used to construct this process invocation.
@{schema_version=2;abi=$Abi;emulator=$Emulator;gpu_requested=$Gpu;gpu_effective=$gpuMode;arguments=@($arguments)} |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "$run/emulator-launch.json" -Encoding utf8
& python "$PSScriptRoot/android-api21-identity.py" capture --root $root --run $run --abi $Abi
if ($LASTEXITCODE) { throw 'Cannot bind API21 launch to prepared emulator/media' }
$previousPath = $env:PATH
$previousAvdHome = $env:ANDROID_AVD_HOME
$previousSdkRoot = $env:ANDROID_SDK_ROOT
try {
    if ($Abi -ne 'armeabi-v7a') {
        $env:ANDROID_AVD_HOME = $avdHome
        $env:ANDROID_SDK_ROOT = $sdkRoot
    }
    $env:PATH = "$(Split-Path -Parent $emulator)/lib;" + $previousPath
    $emulatorOwner=Start-AndroidOwnedProcess -Program $emulator -Arguments $arguments -Directory $run -ArtifactRoot $root -ArtifactLease (Get-AndroidArtifactLockStream $root) -AdbEndpoint (Get-AndroidAdbEndpoint)
} finally {
    $env:PATH = $previousPath
    $env:ANDROID_AVD_HOME = $previousAvdHome
    $env:ANDROID_SDK_ROOT = $previousSdkRoot
}
if ($PassThru) { return $emulatorOwner }
Write-Output "Started API21 emulator PID $($emulatorOwner.Owner.frontend_pid), supervisor $($emulatorOwner.Owner.supervisor_pid), emulator-5582"

} finally { if ($startupLease) { $startupLease.Dispose() } }
