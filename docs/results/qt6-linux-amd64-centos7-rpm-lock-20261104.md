# Qt 6 Linux amd64: clean build from locked CentOS RPMs

On 2026-11-04, Qt 6.8.5 was built from the working tree based on
`2635347ff478131685c8d6bc25e0f2180a247ceb` with the CentOS RPM lock changes.
The build took 72.5 minutes and completed all 12,745 Ninja steps.

| Check | Result |
|---|---|
| Capture from the original yum transactions on CentOS 7.9.2009 | 197 RPMs: 1 SCL release package, 193 build packages and 3 final runtime packages |
| Private backup | All 197 RPMs verified against the lock; the backup also holds a copy of the lock |
| Clean Docker build | Exit 0 with `--no-cache` and `--network=none`; all three yum transactions used local RPMs |
| Installed package inventory | All 335 RPM database entries match the original build's package transactions and base image |
| Consumer smoke test | A Qt Widgets application built against the new SDK and ran on XCB under Xvfb, reporting Qt 6.8.5 and exit 0 |

Build command:

```sh
make -j1 qt6-linux-amd64 NO_CACHE=1 PARALLEL_JOBS=4 \
  QT6_LINUX_AMD64_IMAGE=qt6-linux-amd64:centos7-rpm-lock-check \
  DOCKER_BUILD_FLAGS="--network=none --progress=plain"
```

All archives were already staged locally. BuildKit resolved the pinned
base image metadata through GHCR. The network was disabled in the Docker
build steps and in the smoke container. Qt reported that the smoke
container had only a non-UTF-8 locale available; the application
completed successfully.

- Local image ID: `sha256:7c41b21e376019cfcc5be848d99f6df265ce7aff06213b07a7250942f40271b8`
- [RPM lock](../../scripts/fetch/locks/qt6-centos7-x86_64-packages.json)
  SHA256: `2eb58eb306f4d679c3eea7ce564eb597739080dcf97025841279a2bfad13fc8a`
- Local evidence: `build/qt6-centos7-offline/`
