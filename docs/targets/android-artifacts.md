# Android generations, packaging and result coverage

Use the independent `sdk`, `examples`, `package` and `test` modes in each
target guide. Run native builds and emulator guests sequentially. Saved-APK
packaging and tests consume an existing generation and never build Qt.

## Completed generations and ownership

Each phase holds an OS file lease on `.longreach-artifacts.lock` in its output
root. Nested phases reuse the owning handle; the file's presence alone is not
a lock. Direct package entry points and Python collectors use the same lease.

| Phase | Completion record | Bound inputs |
| --- | --- | --- |
| SDK | `sdk-report-inventory.json` | Exact producer report set and hashes |
| Export | `sdk-report-source.json` | Verified inventory and immutable SDK image |
| Examples | `examples-manifest.json` | SDK, ABI, native sources, runtime and deployments |
| Package | `apk-manifest.json` | Native generation, packaging inputs, keys and APK hashes |
| Test | Case receipts and final results | APK generation, guest/media, coverage and cleanup evidence |

Examples and package modes reserve an in-progress marker before modifying
outputs. Failure leaves the marker and prevents later consumption. Stop the
producer, verify ownership has ended, archive the failed logs/marker and rerun
the entire failed phase. Never mark a partial generation complete manually.
Old outputs missing the current receipt chain require an explicit refresh.
Saved-APK tests retain the report snapshot and image-ID files; Qt5/6 do not
need the original SDK/deployment directories for that phase.

Packaging captures Java adapters, scripts, Build Tools 36.0.0, platform 35
jar/AIDL, the actual compiler JDK and JAVA_HOME/PATH runtimes. Recursive JDK
inputs include `ct.sym`; only `src.zip` is excluded. Tool hashes use relative
labels, with host roots stored separately. Development keys are established
before capture and reused. Completion rechecks all captured inputs and keys.
A Java-only host-adapter edit can be repackaged; changing native deployments,
the runtime or the SDK's Java template/JAR requires examples mode.

Qt4 API10/21 uses schema3 native/APK receipts and twelve JNI clients.
`apk-packages.json` records each profile; the aggregate APK manifest binds it
to the native generation and packaging inputs. Embedded JNI/runtime bytes
must match. Tests use saved native files and report snapshots without a Docker
build. API4 has its own `donut-native-*`/`donut-apk-*` receipts; see the
[Donut guide](qt4-android-donut.md).

Qt4's retained source/client caches are separate from disposable run outputs.
An occupied client volume/container slot refuses a new producer. Inspect and
recover an interrupted container explicitly; do not purge its cache as part
of routine rebuilds. Installed mkspecs have their own exact export receipt and
must work independently of the retained source tree.

## SDK and packaged native metadata

SDK exports verify the exact producer inventory before replacing reports.
Qt4 uses `sdk-reports/`; Qt5/6 retain flat report paths. Previous snapshots go
to `sdk-report-history/`; identical verified snapshots retain timestamps.
Report refreshes preserve native caches, APKs and individual runs.

APK metadata requires a complete little-endian ET_DYN ELF header for the
selected class/machine. ARM additionally requires compatible EABI5/base-float
attributes. Producer reports check selected relocation/ABI metadata; those
checks do not establish full loader resolution or native execution.
API10 Qt5 producers also require API21 symbol-name availability reports.
These are static availability checks; loading the APK remains a guest test.

Current runtime recipes place LLVM's generic atomic provider once in
`libc++_shared.so`; `runtime-atomic-exports.txt` is a required producer report.
Export metadata does not qualify cross-DSO contention or static client links.
Historical SDKs lacking current reports are not backfilled automatically.

## Qualification gates

[`android-baselines.json`](../../scripts/run/android/android-baselines.json)
defines per-Qt/API/ABI PASS floors, permitted SKIPs and required named results.
Runners and final collectors apply the same policy. Outcomes must be unique
and agree with their summary. Review actual platform reports before changing
a baseline; extra passing checks do not replace a required capability.

| Profile | Complete suite |
| --- | --- |
| Qt4 API10/21 installed SDK | 12 cases, including Android input/lifecycle instrumentation |
| Qt5 API10 ARMv7 / x86 | 13 / 14 cases; x86 starts with `atomic-cow` |
| Qt5 API21 | 13 cases, including core/extended and both galleries |
| Qt6 API21 | 11 cases, including both galleries |

API4 retains its smaller matrix and intentional multimedia/OpenGL omissions.
Strict C++23 independently requires all 25 named checks, exactly 25 PASS,
zero FAIL and zero SKIP. Ordinary device/platform SKIPs remain explicit.
Qt5/6 also require the four timed mutex/semaphore results and observations:
wakeups wait at least 100ms, timeouts at least 150ms, each below 4500ms, with
an unavailable resource before arming and a joined worker. At most three
fast-path setup retries are allowed. These observations do not trace syscalls.
The core selftest floors are Qt5 API10=213, Qt5 API21=212 and Qt6=296 (x86=297).
Changing those native checks requires examples mode, not merely repackaging.

Guest CPU receipts bind `/proc/cpuinfo` and the baseline decision. Every x86
processor needs SSSE3; x86_64 additionally needs cx16, lahf_lm, pni, popcnt,
sse4_1 and sse4_2. AVX is not required. Kernel flags are metadata, not an
instruction-execution probe. ARM evidence carries no x86 feature claim.

## Standalone API10 case state

`scripts/run/qt5-android-gingerbread.ps1` owns both the artifact root and case
directory. Use `-ArtifactRoot` for custom layouts and keep case outputs
separate from APK/media/SDK/script inputs and the artifact root itself.
Each attempt reserves an ID-bound pending marker, then archives the complete
prior attempt under `previous-<id>/`. Failed preflight preserves prior bytes;
interrupted history is retained for recovery. No automatic history purge runs.

Suites create a fresh `batch-receipt.json` binding the SDK, APK manifest,
ABI/API and emulator hash. Case receipts bind that batch, APK/stdout hashes,
power policy and attempt identity; collectors reject pending or mixed batches.
APK/manifest bytes are rechecked across installation, execution and cleanup.
A standalone case or `RuntimeProbe` has `qualification=false` and cannot be
merged into a qualified suite. A new failed collection clears old aggregate
results while preserving individual attempts.

## Observed process termination

Qt5 API10 and Qt5/6 API21 require a native zero return marker followed by a
matching application start/death PID pair and two logcat/ps observations of
absence. Restarts, debuggerd crashes, fatal errors or forced app termination
fail the case. `process-exit.json` binds the observed logs/PID; collectors
recheck it. This is observed termination, not an OS exit-status capture.

API21 additionally retains post-release raw/scoped logs per case before the
next log reset, plus an owner-bound `final-logcat-capture.json`. Selected and
WAV runs use the same final-capture checks. API10 completes its receipt only
after final logs and owned-emulator shutdown. Historical reports missing this
chain remain historical; see the [old exit-evidence correction](../results/qt5-android-api10-exit-evidence-20261123.md)
and [later measured sensor result](../results/qt5-api10-sensor-queue-lifecycle-20261123.md).

## Resident Qt4 case release and final capture

Qt4 ProbeActivity records JNI return while remaining resident. Runners then
force-stop/uninstall the package and capture raw/scoped logs before the next
profile resets logcat. Case hashes and the final owner-bound capture preserve
that observation and reject fatal cleanup. Instrumentation has its own bounded
completion check. This establishes resident-JNI cleanup, not natural JVM/native
destructor exit. Selected-profile runs retain evidence without a full aggregate.

## API21 launch classification

`emulator-launch.json` records argv/effective GPU; `run-options.json` records
application options. Cases bind both and the canonical app/APK pairing.
Plugin debugging, `-QtQuickBackend software` and `-Gpu mesa` are diagnostics:
even a complete passing run has `qualification=false`. Intel `on` and `mesa`
both use SwiftShader GLES, but the nondefault request keeps its diagnostic
classification. API10's software Qt Quick baseline remains ordinary there.

`emulator-media.json` and `emulator-identity.json` bind pinned archives,
prepared frontend/backend dependencies, kernel, ramdisk, system, initial
userdata, argv and CPU configuration. QEMU2 AVD inputs are snapshotted before
launch. Immutable media are checked again after cleanup; guest data remain
writable. Extraction caches verify their archive/recipe/file inventory and
preserve old or interrupted staging for explicit recovery.

## Host process ownership and completion receipts

Emulator runners require Windows 10+, PowerShell 7 and Python 3.11+.
The supervisor starts the frontend inside a Windows Job Object and owns its
descendants. Parent death and cleanup terminate that owned tree, including
engines surviving frontend exit. A bounded grace precedes forced host shutdown;
this host policy remains separate from application natural-exit checks.

`host-process-request.json`, `host-process-owner.json` and
`host-process-exit.json` bind argv, original owner, empty final tree and closed
logs. `emulator.pid` is the frontend; `emulator-supervisor.pid` is the retained
supervisor. Collectors require matching emulator invocation and root-lease
lifetime. The supervisor retains a duplicate lease until shutdown completes.
Old receipts must not be reconstructed as evidence of a new run.

Backend `windows-job-startup-v2` also holds a non-waiting Global Windows mutex
until the owned tree exits. This coordinates Longreach emulator trees across
checkouts, not unmanaged programs or SDK producers. Read-only emulator process
preflight checks producers and runners without stopping unrelated software.
Use the suite/raw runner for lifecycle management; a caller using the starter's
`-PassThru` must keep its PowerShell owner alive for the guest lifetime.

## ADB endpoint and command deadlines

To select a separate local ADB endpoint, set both variables in the invoking
PowerShell process (choose a free port):

```powershell
$env:ADB_SERVER_SOCKET = 'tcp:localhost:5048'
$env:ANDROID_ADB_SERVER_PORT = '5048'
./scripts/build/qt5-android.ps1 -Mode test -Abi x86 -RunName suite-1
```

Socket-only or port-only settings also work; conflicting choices fail. The
request freezes a loopback endpoint for frontend and explicitly addressed
clients. Ambient environment changes cannot redirect an active bound run.
The scripts do not own or automatically stop the shared ADB daemon. Automatic
private-server lifecycle and exclusive device discovery remain unimplemented.

Ordinary ADB requests have 15s budgets, `am`/`pm` 30s and transfers/install/remove
180s. Classic x86 API10 APK push allows 600s and records elapsed time in
`apk-push.json`. Native diagnostic probes use 180s. Execution and output drain
share a budget; client timeout cleanup allows one additional second. Boot,
process-exit and final-log queries have their own shorter deadlines.

For an already-built corrected classic x86 frontend, pass
`-Emulator /absolute/path/to/emulator-x86.exe` to Qt5 test mode. Adjacent BIOS
files must exist. The suite uses classic arguments and requires the COW case;
it never builds or patches an emulator. Other ABIs/modes reject the override.

## Focused diagnostics and script layout

The shared API21 runner supports `-QtMajor 5 -Api10Compatibility -Abi x86`
(or `armeabi-v7a`) for one ready API10 core APK on an API21 guest. It preserves
the API10 policy and writes `api10-on-api21-result.json`, always a diagnostic.
`-QtMajor 5 -SoundCacheTeardown` instead selects the extended WAV diagnostic
and `sound-cache-result.json`. These routes use normal generation/exit/final-log
checks; neither replaces a full suite or qualifies untested ABIs.

The standalone Qt6 probe consumes five separately built inputs under `probe/`:
`cxx23-probe`, `libc++_shared.so`, `atomic-probe` and two atomic worker DSOs.
Remote mkdir/chmod success and each input hash are recorded. Its cross-DSO
output must identify the common provider, two workers, 24-byte handoff and one
zero exit. Source fixtures alone do not qualify compilation or guest contention.

Public entry points stay under `scripts/run/`; shared Android implementations
live under `scripts/run/android/`, target build helpers under `scripts/build/`,
and Android fixtures under `scripts/tests/android/`. CI lists the corresponding
fixtures. Build recipes and reusable checks stay public; local working diaries
and raw lab protocols live in the private test lab, as for other targets.
Historical result reports identify their tested SDKs and never qualify changed
producer recipes, current source or other ABIs by implication.

API10 packaging additionally checks all nine native application deployments
against direct DT_NEEDED providers and the sealed API21 platform export context.
This requires a new SDK report format and an explicit SDK/examples refresh;
packaging does not download an NDK or implicitly rebuild a historical SDK.
The checker's reusable implementation is under `scripts/build/android-api21/`.

The owned-host `frontend_signaled` field means a signaled Windows process handle
after wait, not a delivered shutdown signal; the receipt states its passive
grace/Job-termination policy explicitly.
