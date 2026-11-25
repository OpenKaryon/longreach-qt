# SPDX-License-Identifier: GPL-3.0-or-later
# Actual legacy producer + real generation validators, recorded build/packaging boundaries.
param([string]$RepoRoot=(Resolve-Path "$PSScriptRoot/../../..").Path)
$ErrorActionPreference='Stop'
. "$RepoRoot/scripts/run/android/android-owned-process.ps1"
$parent=(New-Item -ItemType Directory -Force "$RepoRoot/build/fixtures").FullName
$fixture=Join-Path $parent ('android-donut-producer-'+[guid]::NewGuid())
$global:DonutProducerFixture=@{RealRepo=$RepoRoot;Repo="$fixture/repo";Home=$fixture;Mode='';Root='';
    Python=(Get-Command python -CommandType Application | Select-Object -First 1).Source;
    Calls=[Collections.Generic.List[string]]::new()}
function Get-Process {
    param($Name,$ErrorAction)
    if ($global:DonutProducerFixture.Mode -in @('other-emulator','runner-other-emulator')) {
        if ($Name -notcontains 'qemu-system-i386-headless') { throw 'API4 process preflight missed another platform engine' }
        return [pscustomobject]@{Name='qemu-system-i386-headless'}
    }
    return $null
}
function Start-Process { throw 'Recorded emulator launch boundary; no process starts' }
function Assert-DonutProducer([bool]$Value,[string]$Reason) { if (!$Value) { throw $Reason } }
try {
    New-Item -ItemType Directory -Force $fixture | Out-Null
    @'
import hashlib, importlib.util, json, pathlib, sys, zipfile
real, home = map(pathlib.Path, sys.argv[1:3])
repo, inputs = home/'repo', home/'inputs'
spec = importlib.util.spec_from_file_location('api4_recorded_producer', real/'scripts/build/qt4-android/donut-artifacts.py')
module = importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
action = sys.argv[3]
if action == 'seed':
    for relative in module.SOURCE_TREES:
        path=repo/relative/'fixture.txt';path.parent.mkdir(parents=True,exist_ok=True);path.write_text(relative)
    for relative in (*module.SOURCE_FILES,'scripts/build/qt4-android/package.ps1', 'scripts/build/qt4-android/host.ps1',
                     'scripts/build/qt4-android/donut-artifacts.py','scripts/build/android-api21/host-tools.py',
                     'scripts/build/android-api21/artifact-manifest.py','scripts/build/android-api21/native-abi.py',
                     'scripts/build/android-api21/packaging-host.ps1','tests/android-donut/java/ProbeActivity.java'):
        (repo/relative).parent.mkdir(parents=True,exist_ok=True);(repo/relative).write_text('data-only fixture')
    pins={}
    for relative in module.ARCHIVES:
        path=inputs/relative.split('/',1)[1] if relative.startswith('android-inputs/') else repo/relative
        path.parent.mkdir(parents=True,exist_ok=True)
        if path.suffix=='.zip':
            with zipfile.ZipFile(path,'w') as archive:
                archive.writestr(module.JAR_MEMBER,b'API4 fixture jar')
                for member in ('kernel-qemu','ramdisk.img','system.img','userdata.img'):
                    archive.writestr('android-1.6_r03-linux/images/'+member,('data-only image/'+member).encode())
        else:path.write_text(relative)
        pins[relative]=module.common.digest(path)
    (home/'expected-pins.json').write_text(json.dumps(pins))
    tools=inputs/'tools_r24.4.1-windows.zip'
    with zipfile.ZipFile(tools,'w') as archive:
        archive.writestr('tools/emulator-arm.exe',b'data only, never executed')
        archive.writestr('tools/lib/fixture.dll',b'data-only dependency')
    (home/'media-pins.json').write_text(json.dumps({
        'android-1.6_r03-linux.zip':pins['android-inputs/android-1.6_r03-linux.zip'],
        tools.name:module.common.digest(tools)}))
    (home/'sdk/build-tools/36.0.0').mkdir(parents=True)
    (home/'sdk/build-tools/36.0.0/d8.bat').write_text('not executed')
    (home/'javac.exe').write_text('not executed')
elif action=='native':
    sys.path.insert(0,str(real/'scripts/tests/android'));import android_native_abi_fixtures as abi
    stage=pathlib.Path(sys.argv[4])
    for profile in module.PROFILES:
        (stage/(profile+'.so')).write_bytes(abi.elf('armeabi',profile.encode()))
        (stage/(profile+'-elf.txt')).write_text('recorded ELF metadata')
    (stage/'libQtCore.a').write_bytes(b'!<arch>\nFIXTURE')
elif action=='package':
    root,profile=pathlib.Path(sys.argv[4]),sys.argv[5]
    with zipfile.ZipFile(root/(profile+'.apk'),'w') as archive:
        archive.writestr('lib/armeabi/libdonut_probe.so',(root/'native'/(profile+'.so')).read_bytes())
        archive.writestr('AndroidManifest.xml',b'recorded manifest');archive.writestr('classes.dex',b'recorded dex')
    (root/(profile+'.apk.badging.txt')).write_text("sdkVersion:'4'\nnative-code: 'armeabi'\n")
elif action=='metadata':
    name=pathlib.Path(sys.argv[4]).name
    arguments=sys.argv[5:]
    if name=='android-donut-state.py':
        spec=importlib.util.spec_from_file_location('api4_recorded_state',real/'scripts/run/android/android-donut-state.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        module.artifacts.ARCHIVES=json.loads((home/'expected-pins.json').read_text())
        module.prepared.PINS=json.loads((home/'media-pins.json').read_text())
    elif name=='prepare-media.py':
        spec=importlib.util.spec_from_file_location('api4_recorded_media',real/'scripts/build/qt4-android/prepare-media.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        archive=pathlib.Path(arguments[arguments.index('--archive')+1])
        selected=arguments.index('--sha256')+1
        if arguments[selected]!=module.PINS[archive.name]:raise RuntimeError('Host wrapper did not pass the repository pin')
        module.PINS=json.loads((home/'media-pins.json').read_text())
        arguments[selected]=module.PINS[archive.name]
    else:module.ARCHIVES=json.loads((home/'expected-pins.json').read_text())
    module.common.REPO=repo
    module.common._host_tools.snapshot=lambda sdk,javac,android_jar: {'schema_version':2,'tool_sha256':{'android-platform/android.jar':module.common.digest(pathlib.Path(android_jar)),'recorded_compiler':module.common.digest(pathlib.Path(javac))}}
    try:module.main(arguments) # Only fixture pins differ; all metadata/extraction logic is real.
    except (OSError,ValueError,KeyError,RuntimeError,zipfile.BadZipFile) as error:
        print('API4 recorded validator: '+str(error),file=sys.stderr);sys.exit(1)
else:raise RuntimeError('Unexpected fixture action')
'@ | Set-Content "$fixture/data.py" -Encoding utf8
    & $global:DonutProducerFixture.Python "$fixture/data.py" $RepoRoot $fixture seed
    if ($LASTEXITCODE) { throw 'Could not seed API4 data fixture' }
    foreach ($relative in @('scripts/run/android/android-adb-endpoint.ps1','scripts/run/android/android-emulator-state.ps1','scripts/build/qt4-android.ps1','scripts/run/qt4-android-donut.ps1','scripts/run/android/android-owned-process.ps1','scripts/build/android-api21/artifact-lock.ps1')) {
        $target=Join-Path $global:DonutProducerFixture.Repo $relative
        New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
        Copy-Item -LiteralPath (Join-Path $RepoRoot $relative) -Destination $target
    }
    @'
. "$($global:DonutProducerFixture.RealRepo)/scripts/run/android/android-owned-process.ps1"
function Start-AndroidOwnedProcess { throw 'Recorded emulator launch boundary; no process starts' }
'@ | Set-Content "$fixture/repo/scripts/run/android/android-owned-process.ps1"
    @'
function Invoke-AndroidAdb { return 'recorded ADB start-server' }
'@ | Set-Content "$fixture/repo/scripts/run/android/android-adb.ps1"
    @'
function Invoke-DonutCommand([string]$Program,[string[]]$Arguments) {
    $context=$global:DonutProducerFixture
    $context.Calls.Add($Program+'|'+($Arguments -join '|'))
    Get-AndroidArtifactLockStream $context.Root | Out-Null
    $global:LASTEXITCODE=0
    if ($Program -eq 'python') {
        $name=[IO.Path]::GetFileName($Arguments[0])
        if ($name -eq 'android-baselines.py') {
            & $context.Python "$($context.RealRepo)/scripts/run/android/android-baselines.py" @($Arguments | Select-Object -Skip 1)
        } elseif ($name -eq 'require-modern-cpp.py') {
            & $context.Python "$($context.RealRepo)/scripts/tests/require-modern-cpp.py" @($Arguments | Select-Object -Skip 1)
        } else { & $context.Python "$($context.Home)/data.py" $context.RealRepo $context.Home metadata @Arguments }
        if ($LASTEXITCODE) { throw 'API4 generation validator refused recorded operation' }
        return
    }
    if ($Program.Replace('\','/') -like '*/platform-tools/adb.exe') { return 'recorded ADB start-server' }
    if ($Program -ne 'docker') { throw 'Unexpected native tool' }
    switch ($Arguments[0]) {
        'build' { return }
        'image' { return ('sha256:'+('d'*64)) }
        'run' {
            if ($Arguments -notcontains ('sha256:'+('d'*64)) -or $Arguments -contains 'longreach-qt4-android-donut:llvm21') { throw 'Native run used mutable image tag' }
            $mount=@($Arguments | Where-Object { $_ -like 'type=bind,source=*,target=/out' })
            if ($mount.Count -ne 1 -or $mount[0] -notmatch '^type=bind,source=(.+),target=/out$') { throw 'Missing native output mount' }
            $stage=$Matches[1]
            if ([IO.Path]::GetFileName($stage) -notmatch '^native-build-[0-9a-f]{32}$') { throw 'Native run reused old output directory' }
            & $context.Python "$($context.Home)/data.py" $context.RealRepo $context.Home native $stage
            if ($LASTEXITCODE) { throw 'Could not seed recorded native output' }
            if ($context.Mode -eq 'native-failed') { throw 'Recorded native build failure' }
            return
        }
        default { throw 'Unexpected Docker action' }
    }
}
__REAL_API4_EXPAND_FUNCTION__

function Get-AndroidPackagingJava {
    $path="$($global:DonutProducerFixture.Home)/javac.exe"
    return @{javac=$path;launcher=$path}
}
function Initialize-DonutSigningKey($OutputDirectory,$JavaDirectory) {
    if ($global:DonutProducerFixture.Mode -eq 'key-failed') { throw 'Recorded key initialization failure' }
    'recorded initial key' | Set-Content "$OutputDirectory/local-probe.jks"
    return "$OutputDirectory/local-probe.jks"
}
'@ | Set-Content "$fixture/repo/scripts/build/qt4-android/host.ps1"
    $hostTokens=$null;$hostErrors=$null
    $hostAst=[Management.Automation.Language.Parser]::ParseFile("$RepoRoot/scripts/build/qt4-android/host.ps1",[ref]$hostTokens,[ref]$hostErrors)
    if ($hostErrors.Count) { throw 'Actual API4 host source failed parsing' }
    $expandAst=$hostAst.Find({param($node);$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Expand-DonutInput'},$true)
    if (!$expandAst) { throw 'Missing actual API4 archive wrapper' }
    $hostPath="$fixture/repo/scripts/build/qt4-android/host.ps1"
    $hostText=[IO.File]::ReadAllText($hostPath).Replace('__REAL_API4_EXPAND_FUNCTION__',$expandAst.Extent.Text)
    [IO.File]::WriteAllText($hostPath,$hostText,[Text.UTF8Encoding]::new($false))
    @'
param($Profile,$NativeDirectory,$OutputDirectory,$AndroidSdk,$AndroidJar,$JavaTools)
$context=$global:DonutProducerFixture
$context.Calls.Add('package|'+$Profile)
Get-AndroidArtifactLockStream $OutputDirectory | Out-Null
if (!$JavaTools -or !(Test-Path "$OutputDirectory/donut-apk-in-progress.json") -or !(Test-Path "$OutputDirectory/local-probe.jks")) { throw 'Package began without frozen Java/key/native reservation' }
if ($context.Mode -eq 'package-failed' -and $Profile -eq 'core') { throw 'Recorded package failure' }
& $context.Python "$($context.Home)/data.py" $context.RealRepo $context.Home package $OutputDirectory $Profile
if ($LASTEXITCODE) { throw 'Recorded packaging metadata failed' }
'@ | Set-Content "$fixture/repo/scripts/build/qt4-android/package.ps1"
    New-Item -ItemType Directory -Force "$fixture/sdk/platform-tools" | Out-Null
    'data only, never executed' | Set-Content "$fixture/sdk/platform-tools/adb.exe"
    foreach ($mode in @('ready','native-failed','key-failed','package-failed','locked','owned','other-emulator')) {
        $context=$global:DonutProducerFixture
        $context.Mode=$mode;$context.Calls.Clear()
        $root=(New-Item -ItemType Directory "$fixture/out-$mode").FullName
        $context.Root=$root
        'old report' | Set-Content "$root/final-results.json"
        $lock=$null
        try {
            if ($mode -eq 'locked') { $lock=[IO.File]::Open("$root/.longreach-artifacts.lock",'OpenOrCreate','ReadWrite','None') }
            if ($mode -eq 'owned') {
                Initialize-AndroidOwnedProcessRegistry
                $global:LongreachOwnedProcesses['api4-fixture-owner']=[pscustomobject]@{ArtifactRoot=$root;Process=[pscustomobject]@{HasExited=$false}}
            }
            $message=$null
            try { & "$fixture/repo/scripts/build/qt4-android.ps1" -InputDirectory "$fixture/inputs" -OutputDirectory $root -AndroidSdk "$fixture/sdk" | Out-Null }
            catch { $message=$_.Exception.Message }
            if ($mode -eq 'ready') {
                Assert-DonutProducer (!$message) "Normal producer failed: $message"
                $receipt=Get-Content "$root/donut-apk-manifest.json" -Raw | ConvertFrom-Json
                Assert-DonutProducer ($receipt.packages.Count -eq 8) 'Producer did not publish all eight APKs'
                Assert-DonutProducer (@($context.Calls | Where-Object { $_ -like 'package|*' }).Count -eq 8) 'Producer changed profile coverage'
                Assert-DonutProducer (!(Test-Path "$root/donut-native-in-progress.json") -and !(Test-Path "$root/donut-apk-in-progress.json")) 'Completed producer left pending markers'
            } else {
                $expected=switch ($mode) { 'native-failed' { 'native build failure' };'key-failed' { 'key initialization failure' };'package-failed' { 'package failure' };'locked' { 'Another Longreach operation' };'owned' { 'Another owned emulator' };'other-emulator' { 'Stop the Android emulator' } }
                Assert-DonutProducer ($message -match $expected) "Unexpected $mode outcome: $message"
                Assert-DonutProducer (!(Test-Path "$root/donut-apk-manifest.json")) 'Failed producer published APK completion'
                if ($mode -eq 'native-failed') { Assert-DonutProducer ((Test-Path "$root/donut-native-in-progress.json") -and !(Test-Path "$root/native")) 'Failed native staging became a completed generation' }
                if ($mode -eq 'key-failed') { Assert-DonutProducer (!(Test-Path "$root/donut-apk-in-progress.json")) 'Key failure reserved an APK generation prematurely' }
                if ($mode -eq 'package-failed') { Assert-DonutProducer (Test-Path "$root/donut-apk-in-progress.json") 'Failed packaging lost its pending marker' }
            }
            if ($mode -in @('locked','owned','other-emulator')) { Assert-DonutProducer ($context.Calls.Count -eq 0 -and (Get-Content "$root/final-results.json") -ceq 'old report') 'Busy producer changed owner state' }
            else { Assert-DonutProducer (!(Test-Path "$root/final-results.json")) 'Old full report survived native reservation' }
        } finally { if ($lock) { $lock.Dispose() }; if ($global:LongreachOwnedProcesses) { $global:LongreachOwnedProcesses.Remove('api4-fixture-owner') | Out-Null } }
        $check=[IO.File]::Open("$root/.longreach-artifacts.lock",'OpenOrCreate','ReadWrite','None');$check.Dispose()
    }
    $context=$global:DonutProducerFixture
    $root=(Resolve-Path "$fixture/out-ready").Path
    $context.Root=$root
    $originalApk=[IO.File]::ReadAllBytes("$root/core.apk")
    foreach ($mode in @('runner-boundary','runner-stale','runner-pending','runner-busy','runner-duplicate','runner-owned','runner-empty','runner-other-emulator')) {
        $context.Mode=$mode;$context.Calls.Clear()
        'current owner report' | Set-Content "$root/final-results.json"
        $lock=$null
        try {
            if ($mode -eq 'runner-stale') { [IO.File]::WriteAllBytes("$root/core.apk",($originalApk+[byte[]](1,2,3))) }
            if ($mode -eq 'runner-pending') { '{}' | Set-Content "$root/donut-native-in-progress.json" }
            if ($mode -eq 'runner-busy') { $lock=[IO.File]::Open("$root/.longreach-artifacts.lock",'OpenOrCreate','ReadWrite','None') }
            if ($mode -eq 'runner-owned') {
                $global:LongreachOwnedProcesses['api4-fixture-owner']=[pscustomobject]@{ArtifactRoot=$root;Process=[pscustomobject]@{HasExited=$false}}
            }
            $selection=if ($mode -eq 'runner-duplicate') { @('core','CORE') } elseif ($mode -eq 'runner-empty') { @() } else { @('core') }
            $before=@(Get-ChildItem "$root/run" -Directory -ErrorAction SilentlyContinue).Count
            $message=$null
            try { & "$fixture/repo/scripts/run/qt4-android-donut.ps1" -InputDirectory "$fixture/inputs" -OutputDirectory $root -AndroidSdk "$fixture/sdk" -Profiles $selection | Out-Null }
            catch { $message=$_.Exception.Message }
            $expected=switch ($mode) {
                'runner-boundary' { 'Recorded emulator launch boundary' }
                'runner-stale' { 'generation validator refused' }
                'runner-pending' { 'generation validator refused' }
                'runner-busy' { 'Another Longreach operation' }
                'runner-duplicate' { 'Duplicate API4 profile' }
                'runner-owned' { 'Another owned emulator' }
                'runner-empty' { 'Profiles|At least one API4 profile' }
                'runner-other-emulator' { 'An Android emulator is already running' }
            }
            Assert-DonutProducer ($message -match $expected) "Unexpected runner $mode outcome: $message"
            $runs=@(Get-ChildItem "$root/run" -Directory -ErrorAction SilentlyContinue)
            if ($mode -eq 'runner-boundary') {
                Assert-DonutProducer ($runs.Count -eq $before+1) 'Runner overwrote prior attempt data'
                $record=Get-Content "$($runs[-1].FullName)/run-inputs.json" -Raw | ConvertFrom-Json
                Assert-DonutProducer (!$record.completed -and !$record.qualification -and !$record.host_tree_exit_verified) 'Unstarted case claimed qualification/completion'
                Assert-DonutProducer ($record.apk_sha256 -ceq (Get-FileHash "$root/core.apk").Hash.ToLowerInvariant() -and
                    $record.native_manifest_sha256 -ceq (Get-FileHash "$root/donut-native-manifest.json").Hash.ToLowerInvariant() -and
                    $record.apk_manifest_sha256 -ceq (Get-FileHash "$root/donut-apk-manifest.json").Hash.ToLowerInvariant()) 'Runner failed to bind actual native generation/APK bytes'
            } else { Assert-DonutProducer ($runs.Count -eq $before) 'Refused runner created a guest attempt' }
            if ($mode -eq 'runner-other-emulator') {
                Assert-DonutProducer (!@($context.Calls | Where-Object { $_ -like '*prepare-media.py*' }).Count) 'Busy emulator preflight changed the extracted cache'
            }
            if ($mode -in @('runner-busy','runner-duplicate','runner-owned','runner-empty')) {
                Assert-DonutProducer ($context.Calls.Count -eq 0 -and (Get-Content "$root/final-results.json") -ceq 'current owner report') 'Busy/invalid runner changed owner state'
            }
        } finally {
            if ($lock) { $lock.Dispose() }
            $global:LongreachOwnedProcesses.Remove('api4-fixture-owner') | Out-Null
            [IO.File]::WriteAllBytes("$root/core.apk",$originalApk)
            [IO.File]::Delete("$root/donut-native-in-progress.json")
        }
        $check=[IO.File]::Open("$root/.longreach-artifacts.lock",'OpenOrCreate','ReadWrite','None');$check.Dispose()
    }
    # Complete runner with recorded device/host boundaries and real metadata validators.
    $global:AndroidOwnedFixture=@{Repo=$RepoRoot;Python=$context.Python;RecordStart=$false}
    $context.StopCalls=0;$context.CurrentRun='';$context.CurrentProfile='';$context.DevicePolls=0
    @'
import pathlib, sys
real, home=map(pathlib.Path,sys.argv[1:3]);sys.path.insert(0,str(real/'scripts/tests/android'))
import android_result_fixtures as reports
directory=home/'reports';directory.mkdir()
for profile,label in {'strict':'strict','selftest':'qt-selftest','graphics':'graphics','network':'network-gui','painting':'painting-lab'}.items():
    (directory/(profile+'.txt')).write_text(reports.stdout(4,4,'armeabi',profile,label))
(directory/'quick.txt').write_text('\n'.join('PASS: '+name for name in reports.QUICK_CHECKS)+'\n')
'@ | Set-Content "$fixture/reports.py" -Encoding utf8
    & $context.Python "$fixture/reports.py" $RepoRoot $fixture
    if ($LASTEXITCODE) { throw 'Could not seed synthetic API4 reports' }
    @'
. "$($global:DonutProducerFixture.RealRepo)/scripts/tests/android/android-owned-process-mock.ps1"
$global:DonutBaseStart=(Get-Command Start-AndroidOwnedProcess).ScriptBlock
$global:DonutBaseStop=(Get-Command Stop-AndroidOwnedProcess).ScriptBlock
$global:DonutBaseGet=(Get-Command Get-AndroidOwnedProcess).ScriptBlock
function Start-AndroidOwnedProcess {
    param($Program,[string[]]$Arguments,$Directory,$ArtifactRoot,$ArtifactLease)
    $context=$global:DonutProducerFixture
    $context.CurrentRun=$Directory;$context.CurrentProfile=([IO.Path]::GetFileName($Directory) -split '-')[0]
    if (!$ArtifactLease -or !$ArtifactLease.CanRead -or $ArtifactRoot -cne $context.Root) { throw 'API4 launch lost its live root lease' }
    $context.Owner=& $global:DonutBaseStart -Program $Program -Arguments $Arguments -Directory $Directory -ArtifactRoot $ArtifactRoot -ArtifactLease $ArtifactLease
    return $context.Owner
}
function Get-AndroidOwnedProcess($Directory) {
    if ($global:DonutProducerFixture.Mode -eq 'cleanup-lookup') { throw 'Recorded cleanup lookup failure' }
    & $global:DonutBaseGet $Directory
}
function Stop-AndroidOwnedProcess($Control,$GraceMilliseconds) {
    $context=$global:DonutProducerFixture
    $context.StopCalls++
    $result=& $global:DonutBaseStop $Control $GraceMilliseconds
    $Control.Process=$null
    if ($context.Mode -eq 'host-active') {
        $path="$($Control.Directory)/host-process-exit.json"
        $value=Get-Content $path -Raw | ConvertFrom-Json
        $value.active_processes=1
        $value | ConvertTo-Json -Depth 6 | Set-Content $path
        $result.host_process_exit_sha256=(Get-FileHash $path).Hash.ToLowerInvariant()
    }
    return $result
}
'@ | Set-Content "$fixture/repo/scripts/run/android/android-owned-process.ps1"
    @'
function Get-DonutRecordedLog {
    $profile=$global:DonutProducerFixture.CurrentProfile
    $code=if ($profile -eq 'bootstrap') { '42' } else { '0' }
    if ($global:DonutProducerFixture.Mode -in @('case-nonzero','strict-nonzero')) { $code='1' }
    if ($profile -eq 'quick') { return 'I/Quick( 123): recorded rendering' }
    "I/LongreachDonut( 123): Native probe returned $code"
    if ($profile -eq 'core') { 'I/LongreachDonut( 123): QtCore 4.8.7 PASS' }
    if ($profile -eq 'strict') { 'I/LongreachDonut( 123): Classic locale check passed' }
}
function Invoke-AndroidAdb {
    param($Adb,[string[]]$Arguments,[int]$TimeoutMilliseconds,[switch]$AllowNonzero)
    $context=$global:DonutProducerFixture
    $context.Calls.Add('adb|'+($Arguments -join '|'))
    if ($Arguments[0] -eq '-s') {
        if ($Arguments[1] -cne 'emulator-5580') { throw 'Wrong API4 serial' }
        $values=@($Arguments | Select-Object -Skip 2)
    } else { $values=@($Arguments) }
    $command=$values -join '|'
    if ($command -eq 'start-server') {
        if ($context.Mode -eq 'server-timeout') { throw 'Recorded server timeout' }
        return
    }
    if ($command -eq 'devices') {
        if (!$AllowNonzero -or $TimeoutMilliseconds -lt 1 -or $TimeoutMilliseconds -gt 5000) { throw 'Boot query has no bounded poll contract' }
        if ($context.Mode -eq 'boot-timeout') { throw 'Recorded boot query timeout' }
        if ($context.Mode -eq 'worker-dead') { $context.Owner.Process.HasExited=$true }
        if ($context.Mode -eq 'worker-missing') { $context.Owner.Process=$null }
        if ($context.Mode -eq 'boot-nonzero' -and $context.DevicePolls++ -eq 0) { return }
        return ('emulator-5580' + [char]9 + 'device')
    }
    if ($command -eq 'shell|pm|path|android') { return 'package:/system/framework/framework-res.apk' }
    if ($command -like 'shell|getprop|*') {
        switch ($values[2]) {
            'ro.build.version.release' { return '1.6' }
            'ro.build.version.sdk' { if ($context.Mode -eq 'guest-api') { return '5' };return '4' }
            'ro.product.cpu.abi' { return 'armeabi' }
            default { throw 'Unexpected API4 property' }
        }
    }
    if ($values[0] -eq 'push') {
        if ($context.Mode -eq 'push-timeout') { throw 'Recorded push timeout' }
        return 'recorded transfer'
    }
    if ($command -like 'shell|pm|install|*') {
        if ($context.Mode -eq 'install-timeout') { throw 'Recorded install timeout' }
        if ($context.Mode -eq 'install-no-success') { return 'Failure [recorded failure]' }
        if ($context.Mode -eq 'apk-after-install') { Add-Content "$($context.Root)/core.apk" 'late bytes' }
        if ($context.Mode -eq 'manifest-after-install') { Add-Content "$($context.Root)/donut-apk-manifest.json" ' ' }
        return 'Success'
    }
    if ($command -eq 'shell|logcat|-c' -or $command -eq 'shell|input|keyevent|82') { return }
    if ($command -eq 'shell|logcat|-d|-v|brief') { return @(Get-DonutRecordedLog) }
    if ($command -like 'shell|am|start|*') { return 'recorded ActivityManager launch' }
    if ($command -like 'shell|am|instrument|-w|*') {
        if ($TimeoutMilliseconds -ne 55000) { throw 'Instrumentation lost its deadline' }
        if ($context.Mode -eq 'quick-timeout') { throw 'Recorded instrumentation timeout' }
        return 'INSTRUMENTATION_CODE: -1'
    }
    if ($command -like 'shell|cat|*') {
        $lines=@(Get-Content "$($context.Home)/reports/$($context.CurrentProfile).txt")
        if ($context.Mode -eq 'quick-missing') { return @($lines | Select-Object -Skip 1) }
        if ($context.Mode -eq 'quick-duplicate') { return @($lines)+@($lines[0]) }
        if ($context.Mode -eq 'strict-missing') { return @($lines | Where-Object { $_ -notlike 'PASS: *' }) }
        return $lines
    }
    throw "Unexpected recorded ADB command: $command"
}
'@ | Set-Content "$fixture/repo/scripts/run/android/android-adb.ps1"
    @'
function Invoke-AndroidExitQuery {
    param($Adb,$Serial,$Command,$Directory,$Name,$TimeoutMilliseconds,[switch]$AllowNonzero)
    $context=$global:DonutProducerFixture
    if ($Name -eq 'emulator-stop') { return 'recorded stop request' }
    if ($Name -ne 'final-logcat' -or $TimeoutMilliseconds -ne 5000) { throw 'Unexpected final query' }
    if ($AllowNonzero) { throw 'Required final log capture allowed failed query output' }
    if ($context.Mode -eq 'final-query-failed') { throw 'Recorded final query failure' }
    if ($context.Mode -eq 'final-query-empty') { return }
    switch ($context.Mode) {
        'late-debuggerd' { return '*** *** ***' }
        'report-replace' { 'replaced after case' | Set-Content "$Directory/case-logcat.log" }
        'media-change' { Add-Content "$($context.Root)/inputs/tools/emulator-arm.exe" 'changed dependency' }
        'launch-change' {
            $path="$Directory/emulator-launch.json";$value=Get-Content $path -Raw | ConvertFrom-Json
            $value.arguments[[Array]::IndexOf($value.arguments,'-memory')+1]='64'
            $value | ConvertTo-Json -Depth 5 | Set-Content $path
        }
        'owner-rewrite' {
            $path="$Directory/host-process-owner.json";$value=Get-Content $path -Raw | ConvertFrom-Json
            $value.supervisor_creation_filetime='124'
            $value | ConvertTo-Json -Depth 5 | Set-Content $path
        }
        'unused-native' { Add-Content "$($context.Root)/native/painting.so" 'changed unselected native bytes' }
    }
    return @(Get-DonutRecordedLog)
}
'@ | Set-Content "$fixture/repo/scripts/run/android/android-process-exit.ps1"
    Copy-Item -LiteralPath "$RepoRoot/scripts/run/android/android-api21-cleanup.ps1" -Destination "$fixture/repo/scripts/run/android/android-api21-cleanup.ps1"
    $baselineFiles=@{}
    foreach ($relative in @('core.apk','donut-apk-manifest.json','native/painting.so','inputs/tools/emulator-arm.exe')) { $baselineFiles[$relative]=[IO.File]::ReadAllBytes((Join-Path $root $relative)) }
    function Start-Sleep { param($Seconds,$Milliseconds) }
    $faults=@('boot-timeout','worker-dead','worker-missing','guest-api','push-timeout','install-timeout','install-no-success',
        'apk-after-install','manifest-after-install','case-nonzero','quick-timeout','quick-missing','quick-duplicate',
        'strict-missing','strict-nonzero','late-debuggerd','report-replace','media-change','launch-change','owner-rewrite',
        'host-active','cleanup-lookup','unused-native','server-timeout','final-query-failed','final-query-empty')
    foreach ($mode in @('full-ready','focused-ready','boot-nonzero')+$faults) {
        $context.Mode=$mode;$context.StopCalls=0;$context.CurrentRun='';$context.DevicePolls=0;$context.Calls.Clear()
        $beforeNames=@(Get-ChildItem "$root/run" -Directory | Select-Object -ExpandProperty Name)
        $before=$beforeNames.Count
        foreach ($name in @('final-results.json','final-results-table.md','apk-native-abi-check.json','apk-architecture-final.json','screenshots.json')) {
            'old full PASS' | Set-Content (Join-Path $root $name)
        }
        $selection=if ($mode -like 'quick-*') { @('quick') } elseif ($mode -like 'strict-*') { @('strict') } else { @('core') }
        $options=@{InputDirectory="$fixture/inputs";OutputDirectory=$root;AndroidSdk="$fixture/sdk"}
        if ($mode -ne 'full-ready') { $options.Profiles=$selection }
        $message=$null
        try { & "$fixture/repo/scripts/run/qt4-android-donut.ps1" @options | Out-Null }
        catch { $message=$_.Exception.Message }
        $newRuns=@(Get-ChildItem "$root/run" -Directory)
        if ($mode -in @('full-ready','focused-ready','boot-nonzero')) {
            if ($message) {
                Write-Output ("Fixture failure profile={0} mode={1}" -f $context.CurrentProfile,$mode)
                Get-Content "$($context.CurrentRun)/case-logcat.log" -ErrorAction SilentlyContinue | Write-Output
                Get-ChildItem $context.CurrentRun -Filter '*guest.stdout' | ForEach-Object { Get-Content $_.FullName -Tail 2 | Write-Output }
            }
            Assert-DonutProducer (!$message) ("Normal API4 runner failed for {0}: {1}" -f $mode,$message)
            $expected=if ($mode -eq 'full-ready') { 8 } else { 1 }
            Assert-DonutProducer ($newRuns.Count -eq $before+$expected -and $context.StopCalls -eq $expected) 'Runner coverage or cleanup count changed'
            foreach ($directory in @($newRuns | Where-Object { $_.Name -notin $beforeNames })) {
                $record=Get-Content "$($directory.FullName)/run-inputs.json" -Raw | ConvertFrom-Json
                Assert-DonutProducer ($record.completed -and $record.host_tree_exit_verified -and !$record.qualification) 'Completed diagnostic lacks host proof or claims full qualification'
            }
        } else {
            $expected=switch ($mode) {
                'boot-timeout' { 'boot query timeout' };'worker-dead' { 'tree exited|Required final Android log capture' };'worker-missing' { 'tree exited|Required final Android log capture' };'guest-api' { 'Unexpected guest' }
                'push-timeout' { 'push timeout' };'install-timeout' { 'install timeout' };'install-no-success' { 'APK install failed' }
                'apk-after-install' { 'Artifact bytes differ' };'manifest-after-install' { 'Artifact bytes differ' }
                'case-nonzero' { 'probe result was absent' };'strict-nonzero' { 'probe result was absent' };'quick-timeout' { 'instrumentation timeout' };'quick-missing' { 'Missing Quick' }
                'owner-rewrite' { 'host launch identity changed' };'final-query-failed' { 'Required final Android log capture' };'final-query-empty' { 'Required final Android log capture' };'cleanup-lookup' { 'cleanup lookup failure' };'server-timeout' { 'server timeout' }
                default { 'generation validator refused' }
            }
            Assert-DonutProducer ($message -match $expected) "Unexpected full runner $mode outcome: $message"
            Assert-DonutProducer ($newRuns.Count -eq $before+1) 'Failed attempt overwrote history or created extra runs'
            if ($mode -eq 'strict-nonzero') {
                $saved=Join-Path $context.CurrentRun 'strict-cxx23-guest.stdout'
                Assert-DonutProducer ((Test-Path -LiteralPath $saved) -and
                    ((Get-Content -LiteralPath $saved -Raw) -match '25 passed')) 'Failed strict JNI return lost its fetched stdout'
            }
            if ($context.CurrentRun) {
                Assert-DonutProducer ($context.StopCalls -eq 1) 'Failed case did not stop its retained tree exactly once'
                $record=Get-Content "$($context.CurrentRun)/run-inputs.json" -Raw | ConvertFrom-Json
                Assert-DonutProducer (!$record.completed) 'Failed case published completed evidence'
            }
            if ($mode -in @('worker-dead','worker-missing','guest-api','push-timeout','install-timeout','install-no-success','apk-after-install','manifest-after-install')) {
                Assert-DonutProducer (!@($context.Calls | Where-Object { $_ -like 'adb|*|am|start|*' -or $_ -like 'adb|*|am|instrument|*' }).Count) 'Refused install/bootstrap launched an application'
            }
        }
        foreach ($name in @('final-results.json','final-results-table.md','apk-native-abi-check.json','apk-architecture-final.json','screenshots.json')) {
            Assert-DonutProducer (!(Test-Path (Join-Path $root $name))) 'API4 attempt inherited an old full aggregate'
        }
        foreach ($relative in $baselineFiles.Keys) { [IO.File]::WriteAllBytes((Join-Path $root $relative),$baselineFiles[$relative]) }
        $leaseCheck=[IO.File]::Open("$root/.longreach-artifacts.lock",'OpenOrCreate','ReadWrite','None');$leaseCheck.Dispose()
    }
    Remove-Variable AndroidOwnedFixture,AndroidOwnedMockControls,DonutBaseStart,DonutBaseStop,DonutBaseGet -Scope Global -ErrorAction SilentlyContinue
    Write-Output "PASS: full API4 runner eight synthetic profiles, focused/retry paths and $($faults.Count) injected faults; actual metadata/coverage/host collectors, no ADB/emulator/native tool executes"

    Write-Output 'PASS: actual API4 producer with real validators/eight recorded packages; immutable image/staging, failure markers, root preservation/release; runner refuses stale/pending/busy/duplicate inputs and binds a fresh unstarted attempt. No build tool/device executes.'
} finally {
    Remove-Variable DonutProducerFixture -Scope Global -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $fixture) {
        $resolved=(Resolve-Path -LiteralPath $fixture).Path
        if ([IO.Path]::GetDirectoryName($resolved) -ne $parent -or [IO.Path]::GetFileName($resolved) -notlike 'android-donut-producer-*') { throw 'Unexpected producer fixture cleanup path' }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
