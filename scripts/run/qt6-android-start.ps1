# SPDX-License-Identifier: GPL-3.0-or-later
param([Parameter(Mandatory)][string]$OutputDirectory, [Parameter(Mandatory)][string]$Emulator,
      [string]$RunName='sdk-suite', [ValidateSet('on','mesa')][string]$Gpu='on')
$ErrorActionPreference='Stop'
$root=(Resolve-Path -LiteralPath $OutputDirectory).Path
$media="$root/media/armeabi-v7a"
if ($RunName -notmatch '^[a-z0-9-]+$') { throw 'Invalid run directory name' }
$run = "$root/$RunName"
if (Get-Process -Name emulator-arm,emulator,qemu-system-armel -ErrorAction SilentlyContinue) { throw 'Another emulator is running' }
# A frozen cache does not execute build jobs; it stays paused during regression runs.
$running = & docker ps --filter status=running --filter ancestor=longreach-qt6-android-lollipop:llvm21 --format '{{.Names}}'
if ($LASTEXITCODE) { throw 'Cannot verify that the build slot is free' }
if ($running) { throw 'Stop the build container before starting the emulator' }
if (Test-Path -LiteralPath $run) { throw 'Archive the previous emulator run explicitly before starting a fresh one' }
New-Item -ItemType Directory -Path $run | Out-Null
Copy-Item -LiteralPath "$media/userdata.img" -Destination "$run/userdata-qemu.img"
$arguments = @('-sysdir',$media,'-datadir',$run,'-system',"$media/system.img",'-kernel',"$media/kernel-qemu",'-ramdisk',"$media/ramdisk.img",'-data',"$run/userdata-qemu.img",'-initdata',"$media/userdata.img",'-no-window','-no-audio','-no-snapshot','-no-snapstorage','-skin','480x800','-partition-size','1024','-memory','1024','-gpu',$Gpu,'-port','5582','-no-boot-anim','-verbose','-show-kernel','-qemu','-cpu','cortex-a8')
$arguments = $arguments | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }
$previousPath = $env:PATH
try {
    $env:PATH = "$(Split-Path -Parent $emulator)/lib;" + $previousPath
    $process = Start-Process -FilePath $emulator -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput "$run/emulator.stdout" -RedirectStandardError "$run/emulator.stderr"
} finally {
    $env:PATH = $previousPath
}
$process.Id | Set-Content -LiteralPath "$run/emulator.pid"
Write-Output "Started API21 emulator PID $($process.Id), emulator-5582"
