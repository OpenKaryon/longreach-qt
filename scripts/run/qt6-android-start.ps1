# SPDX-License-Identifier: GPL-3.0-or-later
param([ValidateSet('armeabi-v7a','arm64-v8a')][string]$Abi = 'armeabi-v7a', [Parameter(Mandatory)][string]$OutputDirectory, [Parameter(Mandatory)][string]$Emulator,
      [string]$RunName='sdk-suite', [ValidateSet('on','mesa')][string]$Gpu='on')
$ErrorActionPreference='Stop'
$root=(Resolve-Path -LiteralPath $OutputDirectory).Path
$media="$root/media/$Abi"
# The API21 ARM64 kernel-qemu is a ranchu kernel (3.10), matching Tools25.
$kernel = 'kernel-qemu'
if ($RunName -notmatch '^[a-z0-9-]+$') { throw 'Invalid run directory name' }
$run = "$root/$RunName"
if (Get-Process -Name emulator-arm,emulator,emulator-ranchu-arm64,emulator64-ranchu-arm64,qemu-system-armel,qemu-system-aarch64 -ErrorAction SilentlyContinue) { throw 'Another emulator is running' }
# A frozen cache does not execute build jobs; it stays paused during regression runs.
$running = & docker ps --filter status=running --filter label=org.openkaryon.longreach-qt.android-api=21 --format '{{.Names}}'
if ($LASTEXITCODE) { throw 'Cannot verify that the build slot is free' }
if ($running) { throw 'Stop the build container before starting the emulator' }
if (Test-Path -LiteralPath $run) { throw 'Archive the previous emulator run explicitly before starting a fresh one' }
New-Item -ItemType Directory -Path $run | Out-Null
Copy-Item -LiteralPath "$media/userdata.img" -Destination "$run/userdata-qemu.img"
$arguments = @('-sysdir',$media,'-datadir',$run,'-system',"$media/system.img",'-kernel',"$media/$kernel",'-ramdisk',"$media/ramdisk.img",'-data',"$run/userdata-qemu.img",'-initdata',"$media/userdata.img",'-no-window','-no-audio','-no-snapshot','-no-snapstorage','-skin','480x800','-partition-size','1024','-memory','1024','-gpu',$Gpu,'-port','5582','-no-boot-anim','-verbose','-show-kernel')
if ($Abi -eq 'armeabi-v7a') {
    $arguments += @('-qemu','-cpu','cortex-a8')
} else {
    # The QEMU2 frontend needs an AVD to choose the ARM64 machine. Keep all
    # configuration and writable guest data within this unique run directory.
    $sdkRoot = Split-Path (Split-Path -Parent $Emulator) -Parent
    $relativeMedia = [IO.Path]::GetRelativePath($sdkRoot, $media).Replace('\','/')
    $avdHome = "$run/avd"
    $avdName = 'longreach-api21-arm64'
    $avdPath = "$avdHome/$avdName.avd"
    New-Item -ItemType Directory -Path $avdPath -Force | Out-Null
    @('avd.ini.encoding=UTF-8', "path=$avdPath", 'target=android-21') |
        Set-Content -LiteralPath "$avdHome/$avdName.ini" -Encoding ascii
    @('avd.ini.encoding=UTF-8','abi.type=arm64-v8a','hw.cpu.arch=arm64',
      'hw.cpu.model=cortex-a57','hw.audioInput=no','hw.audioOutput=no','hw.ramSize=1024','hw.lcd.width=480',
      'hw.lcd.height=800','hw.lcd.density=160','hw.keyboard=yes',
      'hw.gpu.enabled=yes',"image.sysdir.1=$relativeMedia",'tag.id=default',
      'tag.display=Default','target=android-21') |
        Set-Content -LiteralPath "$avdPath/config.ini" -Encoding ascii
    $arguments = @('-avd',$avdName,'-engine','qemu2','-accel','off','-shell-serial',"file:$run/kernel-shell.log") + @($arguments | Where-Object { $_ -ne '-no-audio' })
}
$arguments = $arguments | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }
$previousPath = $env:PATH
$previousAvdHome = $env:ANDROID_AVD_HOME
$previousSdkRoot = $env:ANDROID_SDK_ROOT
try {
    if ($Abi -eq 'arm64-v8a') {
        $env:ANDROID_AVD_HOME = $avdHome
        $env:ANDROID_SDK_ROOT = $sdkRoot
    }
    $env:PATH = "$(Split-Path -Parent $emulator)/lib;" + $previousPath
    $process = Start-Process -FilePath $emulator -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput "$run/emulator.stdout" -RedirectStandardError "$run/emulator.stderr"
} finally {
    $env:PATH = $previousPath
    $env:ANDROID_AVD_HOME = $previousAvdHome
    $env:ANDROID_SDK_ROOT = $previousSdkRoot
}
$process.Id | Set-Content -LiteralPath "$run/emulator.pid"
Write-Output "Started API21 emulator PID $($process.Id), emulator-5582"
