# Android generations, packaging and result coverage

Use the independent `sdk`, `examples`, `package` and `test` modes documented
in each target guide. Packaging and tests consume a saved SDK generation;
they do not build Qt. Run native jobs and emulator guests sequentially.

## Completed generations and ownership

The Qt 5/6 entry points take an operating-system file lease on
`.longreach-artifacts.lock` in the output root for the complete phase, including
testing. Direct package-suite entry points take the same lease. Qt 4 API10/21
uses that lease too. Nested phases in the owning PowerShell process retain
the outer handle; another process fails before changing artifacts. The lease
is released on process termination. The file's presence alone is not a lock.
The internal Python manifest commands are not standalone phase entry points.

Qt 5/6 examples reserve `examples-in-progress.json` before changing outputs.
Successful completion records SDK identity, ABI, native application source
snapshot, SDK producer reports, deployment libraries, runtime and SDK Java
inputs. APK packaging reserves `apk-in-progress.json`, captures the current
host Java adapter, packaging scripts, build-tools 36.0.0 files, platform 35
jar/AIDL, JDK tools, modules/configuration/version, possible JAVA_HOME/PATH Java runtimes
and existing signing-key hashes.
Completion requires those inputs and the native generation to remain unchanged
and records every APK and newly generated development key.

The APK receipt describes the sources and tools actually used. A Java-only
host-adapter edit can be repackaged without recompiling native applications;
the native source snapshot stays attached to its original example generation.
Changing the SDK's JAR/template, native deployment or runtime requires examples
mode. Recording tool hashes is provenance, not a new download lock or a claim
that an arbitrary local JDK has been qualified elsewhere.

A failed phase leaves its in-progress marker and refuses later packaging/tests.
After stopping the producer and verifying that no operation owns the root,
archive the failed logs and marker, remove that marker explicitly, and rerun
the complete failed phase. Do not manually mark a partial generation complete.
Existing schema-1 example generations can be repackaged when their recorded
inputs still match. New APK receipts use schema 2; old APK generations require
an explicit package refresh. Saved-APK test mode retains the receipt chain
without requiring SDK/deployment directories.

Qt 4 API10/21 has a native manifest with ABI, API, immutable SDK identity,
runtime hash and twelve JNI client hashes. Package mode checks all metadata
and actual ELF class/machine for every library before replacing any APK.
Older native manifests need one explicit examples-mode refresh. Direct Qt 4
packaging also checks the ELF ABI, including the API4 profile.

## Qualification gates

`../../scripts/run/android-baselines.json` records per-Qt/API/ABI case limits:
minimum PASS, maximum SKIP and required named PASS results for critical GL and
Qt 5 x86 timed-synchronization checks. Both runners and final collectors apply
them. Additional successful checks are allowed; losing established coverage
or turning a critical PASS into SKIP fails qualification. Deliberate changes
to a baseline require review of the affected platform's actual reports.

Strict C++23 remains an independent canonical gate: all 25 named behaviors,
exactly 25 PASS, 0 FAIL and 0 SKIP. Ordinary Qt/module limitations are separate.
The baseline does not claim that every API or device backend is covered.

API21 final collection requires the complete eleven-case Qt 6 or thirteen-case
Qt 5 run. Qt 4 API10/21 requires twelve cases, including all eight shared apps
and Android input/lifecycle instrumentation. Donut retains its smaller qualified
set and intentional multimedia/OpenGL omissions.

The Qt 5 API10 suite now invokes the committed
`collect-legacy-results.py`. Before installing each APK the runner records its
hash, SDK identity, case, guest ABI and ADB connection settings. Successful
completion binds the stdout hash. The collector requires all thirteen launch
receipts on ARMv7 and all fourteen on x86, including `atomic-cow`; it also requires
native exit zero, correct guest properties, a verified stay-awake power policy, no captured fatal cleanup
error, coverage limits, current APK hashes and matching packaged ELF/runtime.
Every x86 receipt must record the same emulator hash as the COW preflight.
Starting a new API10 suite or final collection removes old aggregate results, so
a failed attempt cannot retain an earlier successful batch summary.
It writes `final-results.json`, `final-results-table.md` and
`apk-native-abi-check.json`. Reports made by older experimental collectors
remain historical evidence and are not silently upgraded to this receipt format.

## Private ADB server used for local qualification

The qualification commands use a separate server to avoid changing another
project's ADB connection. Set both variables in the same PowerShell process
before invoking the target's test mode:

```powershell
$env:ADB_SERVER_SOCKET = 'tcp:localhost:5048'
$env:ANDROID_ADB_SERVER_PORT = '5048'
./scripts/build/qt5-android.ps1 -Mode test -Abi x86 -RunName audit-suite -OutputDirectory artifacts/qt5-android-gingerbread-x86
```

For an already-built patched classic x86 emulator, add
`-Emulator /absolute/path/to/emulator-x86.exe` to the Qt 5 `-Mode test -Abi x86`
command. This path is used for every case with the classic launch arguments;
its adjacent BIOS files must already exist. The suite does not extract SDK
emulator tools over that file. Without an override it uses the pinned SDK tools
and their existing launch arguments. Both paths must pass the COW preflight;
the known affected stock emulator is expected to fail it. No emulator is built
by test mode. Other modes and ABIs reject this override.

The scripts inherit those settings. Other users may choose a free port or their
normal server; these environment assignments are not a global machine change.
The API10 result receipt retains the settings actually used.

## Focused ordinary regression checks

The Python tests `test_android_artifacts.py`, `test_android_native_abi.py`,
`test_android_baselines.py`, `test_android_legacy_results.py` and
`test_qt4_android_cache.py` use small fixtures. The PowerShell mode, generation
and artifact-lock/packaging-policy fixtures need no Qt rebuild or emulator. They are included
in repository CI and remain separate from security suites.
