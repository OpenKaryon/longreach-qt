# Qt 5.15.19 Linux arm64 SDK with LLVM 21.1.8

The 2026-11-11 build used the repository's `qt5-linux-arm64-llvm-examples`
target with four compile jobs. It installed 93 static
Qt archives in `qt5-linux-arm64:llvm21`, including Qt Wayland Client and
Compositor. The SDK uses the existing GPL-enabled profile, with QtWebEngine
excluded. Qt Location retains its Mapbox GL plugin.

The QtQml ARM64 register enum has a signed underlying type so Clang can
represent the invalid-register sentinel. The Mapbox patch deletes an invalid
assignment operator on a RapidJSON type with const fields, gives the Boost conversion
enums an explicit underlying type and makes the projection's float conversion
explicit. These patches apply only to this LLVM profile.

## Ubuntu 14.04.6 LTS arm64

The extracted binaries ran one at a time in the stock Ubuntu 14.04 arm64
container under QEMU. The GUI examples used Xvfb. The container uses its
Ubuntu libraries and the current Docker host kernel.

| Run | PASS | FAIL | SKIP |
|---|---:|---:|---:|
| `qt-selftest --modern-cpp` | 25 | 0 | 0 |
| Seven GUI examples | 231 | 0 | 25 |

The strict C++23 gate verified every named check. The run reported
`__cplusplus=202302`, Clang 21.1.8 and libc++ 21.1.8. The GUI skips cover
optional APIs, modules and backends. The ELF audit confirmed AArch64,
glibc symbols up to 2.18 and static Qt and LLVM C++ runtime linkage.
Security tests were outside the run scope. The
[JSON record](qt5-linux-arm64-llvm21-sdk-20261111.json) includes the image IDs, executable hashes and
per-application results. The patch hashes are from the build inputs.
The later SPDX headers leave the applied hunks unchanged.

## Reproduce

Build and extract the examples using the
[Qt 5 Linux guide](../targets/qt5-linux.md#arm64-with-llvm-2118).
Run the following in PowerShell from the repository root.

```powershell
$suite = (Resolve-Path artifacts/tests-qt5-linux-arm64-llvm21).Path
$out = Join-Path $PWD 'build/runs/qt5-linux-arm64-llvm21-trusty'
New-Item -ItemType Directory -Force -Path $out | Out-Null
docker run --rm --platform linux/arm64 --cpus 2 --memory 3g `
    --mount "type=bind,source=$PWD,target=/src,readonly" `
    --mount "type=bind,source=$suite,target=/suite,readonly" `
    --mount "type=bind,source=$out,target=/out" `
    arm64v8/ubuntu@sha256:5ed16aa332467821529d451800e6fe599d83e30471e91b096752f8696d9bf6e9 `
    bash /src/scripts/tests/qt5-linux-arm64-llvm-trusty.sh
python scripts/tests/require-modern-cpp.py "$out/qt-selftest-modern-cpp.log"
```
