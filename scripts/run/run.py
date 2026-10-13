#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Run a test suite on a target machine and record the result.

    run.py --suite artifacts/tests-<image> --host <name> [--out DIR] [--json FILE]

One flow for every backend: pack the suite with SHA256SUMS, deliver it, check
it on the target, run smoke-runner, collect the logs, and write a runtime
result (schema 1, the format of docs/results/).

Hosts are named in scripts/run/hosts.local.json, which is not tracked (copy
hosts.example.json). Built in, without any configuration:

    docker:<distro>     a stock container: centos-7, ubuntu-16.04,
                        ubuntu-18.04, ubuntu-24.04, debian-13, fedora-latest,
                        arch-latest; ubuntu-10.04-i386 (a local image,
                        scripts/run/lucid-i386-image.sh), ubuntu-16.04-i386,
                        debian-12-i386 for i386 suites and centos-7-arm64,
                        ubuntu-14.04-arm64, ubuntu-16.04-arm64, debian-12-arm64
                        for arm64 ones (Xvfb inside; the runtime libraries
                        a desktop has are installed first)
    qemu:<distro>       an old distribution's userland booted in QEMU under a
                        current kernel, for systems a container host cannot
                        run (64-bit glibc before 2.14 needs the vsyscall
                        page): centos-5-x86_64, debian-4-amd64
    local               this machine, in the current session

Backends in hosts.local.json:

    ssh       {"backend": "ssh", "os": "linux"|"macos", "target": "user@host",
               "ssh_options": ["-i", "key", ...]}
    vmware    {"backend": "vmware", "os": "linux"|"windows", "vmx": "...",
               "user": "...", "password_env": "VAR"}; "direct": true on
               Windows 9x and NT 4 starts smoke-runner.exe without a shell
    virtualbox{"backend": "virtualbox", "os": "linux"|"windows", "vm": "name",
               "user": "...", "password_env": "VAR"}

A guest password is never stored: it is read from the environment variable
password_env names, or asked for on the terminal.
"""
import argparse
import datetime
import getpass
import hashlib
import io
import json
import os
import platform
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
HOSTS = Path(__file__).with_name('hosts.local.json')
SKIP_SUFFIXES = ('.log', '.json', '.gz', '.sha256')
SKIP_NAMES = ('smoke-report.txt', 'SHA256SUMS', 'README.txt', 'build-inputs.json')

DOCKER = {
    'centos-7': ('centos:7.9.2009', 'rhel'),
    'ubuntu-16.04': ('ubuntu:16.04', 'debian'),
    'ubuntu-18.04': ('ubuntu:18.04', 'debian'),
    'ubuntu-24.04': ('ubuntu:24.04', 'debian'),
    'debian-13': ('debian:trixie', 'debian'),
    'fedora-latest': ('fedora:latest', 'fedora'),
    'arch-latest': ('archlinux:latest', 'arch'),
    # 32-bit userlands for the i386 suites (run with --platform linux/386).
    'ubuntu-16.04-i386': ('i386/ubuntu:16.04', 'debian', 'linux/386'),
    # Lucid itself: a local image (scripts/run/lucid-i386-image.sh), since
    # Docker Hub's ubuntu:10.04 is in a format containerd no longer reads.
    'ubuntu-10.04-i386': ('longreach/ubuntu:10.04-i386', 'lucid', 'linux/386'),
    'debian-12-i386': ('i386/debian:12', 'debian', 'linux/386'),
    # The arm64 floors, emulated on an x86 host (binfmt/QEMU).
    'centos-7-arm64': ('arm64v8/centos:7', 'rhel', 'linux/arm64'),
    'ubuntu-14.04-arm64': ('arm64v8/ubuntu:14.04', 'trusty', 'linux/arm64'),
    'ubuntu-16.04-arm64': ('arm64v8/ubuntu:16.04', 'debian', 'linux/arm64'),
    'debian-12-arm64': ('arm64v8/debian:12', 'debian', 'linux/arm64'),
}
# The libraries a desktop has: Xlib for Qt 4, xcb for Qt 5/6. Installing both
# costs little and keeps the backend independent of the suite.
PACKAGES = {
    'debian': ('libgl1 libx11-6 libxext6 libxrender1 libsm6 libice6 libfontconfig1 libfreetype6 '
               'libx11-xcb1 libxcb1 libxcb-glx0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-randr0 '
               'libxcb-render-util0 libxcb-render0 libxcb-shape0 libxcb-shm0 libxcb-sync1 libxcb-xfixes0 '
               'libxcb-xkb1 libxkbcommon0 libxkbcommon-x11-0 fonts-dejavu-core xvfb xauth ca-certificates'),
    'rhel': ('mesa-libGL mesa-libEGL mesa-dri-drivers libX11 libXext libXrender libSM libICE fontconfig freetype libX11-xcb libxcb '
             'xcb-util-image xcb-util-keysyms xcb-util-renderutil xcb-util-wm libxkbcommon libxkbcommon-x11 '
             'dejavu-sans-fonts xorg-x11-server-Xvfb'),
    'fedora': ('mesa-libGL mesa-libEGL libglvnd-opengl libX11 libXext libXrender libSM libICE fontconfig freetype '
               'libX11-xcb libxcb xcb-util-cursor xcb-util-image xcb-util-keysyms xcb-util-renderutil '
               'xcb-util-wm libxkbcommon libxkbcommon-x11 dejavu-sans-fonts xorg-x11-server-Xvfb'),
    # Ubuntu 10.04 and 14.04: older names, and no xkbcommon-x11 (the kit builds
    # xkbcommon statically for both).
    'lucid': ('libgl1-mesa-glx libx11-6 libxext6 libxrender1 libsm6 libice6 libfontconfig1 libfreetype6 '
              'libx11-xcb1 libxcb1 ttf-dejavu-core xvfb xauth ca-certificates'),
    'trusty': ('libgl1-mesa-glx libegl1-mesa libx11-6 libxext6 libxrender1 libsm6 libice6 libfontconfig1 '
               'libfreetype6 libx11-xcb1 libxcb1 libxcb-glx0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 '
               'libxcb-randr0 libxcb-render-util0 libxcb-render0 libxcb-shape0 libxcb-shm0 libxcb-sync1 '
               'libxcb-xfixes0 libxcb-xkb1 fonts-dejavu-core xvfb xauth ca-certificates'),
    'arch': ('mesa libglvnd libx11 libxext libxrender libsm libice fontconfig freetype2 libxcb '
             'xcb-util-cursor xcb-util-image xcb-util-keysyms xcb-util-renderutil xcb-util-wm '
             'libxkbcommon libxkbcommon-x11 ttf-dejavu xorg-server-xvfb'),
}
INSTALL = {
    # Libraries whose names differ between releases (libegl1 and libwayland-egl1
    # from Ubuntu 18.04 on, the -mesa packages before) or that only newer ones
    # have are installed one by one where they exist.
    'debian': ('apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends {p} >/dev/null'
               ' && for x in libegl1 libegl1-mesa libgbm1 libdrm2 libxcb-cursor0 libbrotli1'
               ' libwayland-client0 libwayland-cursor0 libwayland-server0 libwayland-egl1 libwayland-egl1-mesa; do'
               ' DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends $x >/dev/null 2>&1 || true; done'),
    'rhel': ("sed -i -e 's|^mirrorlist=|#mirrorlist=|' -e 's|^#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|' "
             '/etc/yum.repos.d/CentOS-*.repo && yum install -y -q {p} >/dev/null'),
    'lucid': 'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends {p} >/dev/null',
    'trusty': 'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends {p} >/dev/null',
    'fedora': 'dnf install -y -q {p} >/dev/null',
    'arch': 'pacman -Sy --noconfirm --needed {p} >/dev/null',
}

# qemu guests: the image whose userland is booted, and the setup the guest
# runs with networking up. CentOS 5's own vault redirects to HTTPS, which its
# SSL cannot reach any more, so the packages come from kernel.org's copy; the
# image's libselinux is the centosplus build, so that repository is needed for
# the policy tools Xvfb's fonts pull in.
QEMU = {
    'centos-5-x86_64': ('centos:5', 'rhel5'),
    'debian-4-amd64': ('debian/eol:etch', 'debian-old'),
}
QEMU_SETUP = {
    'rhel5': r'''set -e
rm -f /etc/yum.repos.d/*.repo
v=http://archive.kernel.org/centos-vault/5.11
cat > /etc/yum.repos.d/vault.repo <<EOF
[base]
name=CentOS 5.11 base
baseurl=$v/os/\$basearch/
gpgcheck=0
exclude=*.i386 *.i686
[updates]
name=CentOS 5.11 updates
baseurl=$v/updates/\$basearch/
gpgcheck=0
exclude=*.i386 *.i686
[centosplus]
name=CentOS 5.11 centosplus
baseurl=$v/centosplus/\$basearch/
gpgcheck=0
includepkgs=libselinux*
EOF
yum -y -q install mesa-libGL libX11 libXext libXrender libSM libICE fontconfig freetype \
    xorg-x11-server-Xvfb xorg-x11-fonts-base xorg-x11-fonts-misc dejavu-lgc-fonts
''',
    # The image's sources already point at archive.debian.org, whose signing
    # keys have long expired. etch's coreutils has no sha256sum; the guest
    # checks the suite with Perl's shasum instead.
    'debian-old': r'''set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --force-yes libgl1-mesa-glx libx11-6 libxext6 libxrender1 libsm6 libice6 \
    libfontconfig1 libfreetype6 xvfb xfonts-base ttf-dejavu libdigest-sha-perl
''',
}

# Run in a Linux guest from the suite directory: find the user's X session,
# run the suite on it, keep the reports.
LINUX_RUN = r'''
set -u
session=$(pgrep -u "$(id -u)" -n -x gnome-session || pgrep -u "$(id -u)" -n -x xfce4-session \
          || pgrep -u "$(id -u)" -n -x cinnamon-session || pgrep -u "$(id -u)" -n -x mate-session || true)
if [ -n "$session" ]; then
    eval "$(tr '\0' '\n' < /proc/$session/environ | grep -E '^(DISPLAY|XAUTHORITY)=' | sed 's/^/export /')"
fi
export DISPLAY=${DISPLAY:-:0}
{ uname -a; cat /etc/os-release 2>/dev/null || cat /etc/lsb-release; ldd --version 2>&1 | head -1; } > system.txt 2>&1
./smoke-runner {args} > runner.log 2>&1; echo "exit=$?" >> runner.log
'''
MACOS_RUN = r'''
{ sw_vers; uname -a; } > system.txt 2>&1
./smoke-runner {args} > runner.log 2>&1; echo "exit=$?" >> runner.log
'''


def suite_files(suite):
    for path in sorted(suite.iterdir()):
        if path.name in SKIP_NAMES or path.name.endswith(SKIP_SUFFIXES) or path.name.startswith('smoke-'):
            if path.name != 'smoke-runner' and not path.name.startswith('smoke-runner.'):
                continue
        yield path


def executable(info):
    info.mode = 0o755
    return info


def pack(suite):
    """tar.gz of the suite with SHA256SUMS; directories (bundles) travel whole."""
    sums = []
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode='w:gz') as tar:
        for path in suite_files(suite):
            # Windows hosts have no executable bit to carry over.
            tar.add(path, arcname=path.name, filter=executable)
            if path.is_file():
                sums.append(f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n')
        data = ''.join(sums).encode()
        info = tarfile.TarInfo('SHA256SUMS')
        info.size = len(data)
        info.mtime = int(time.time())
        tar.addfile(info, io.BytesIO(data))
    return buffer.getvalue(), ''.join(sums)


def password(host):
    name = host.get('password_env')
    if name and os.environ.get(name):
        return os.environ[name]
    if not sys.stdin.isatty():
        raise SystemExit(f'set {name or "the password_env variable"} or run on a terminal')
    return getpass.getpass(f"password of {host.get('user')} in the guest: ")


def run_docker(host, suite, out, runner_args):
    image, family, *platform = DOCKER[host['distro']]
    data, _ = pack(suite)
    (out / 'suite.tar.gz').write_bytes(data)
    packages = ' '.join([PACKAGES[family]] + host.get('packages', []))
    script = (INSTALL[family].format(p=packages) + ' || { echo INSTALL FAILED; exit 3; }\n'
              '[ -s /etc/machine-id ] || tr -d - < /proc/sys/kernel/random/uuid > /etc/machine-id\n'
              'mkdir /tmp/run && cd /tmp/run && tar -xzf /out/suite.tar.gz && rm /out/suite.tar.gz\n'
              'sha256sum -c SHA256SUMS > /out/checksums.log 2>&1 || { echo CHECKSUM FAILED; exit 4; }\n'
              'chmod -R u+x .\n'
              '{ cat /etc/os-release /etc/lsb-release 2>/dev/null; ldd --version 2>&1 | head -1; } > /out/system.txt\n'
              'Xvfb :99 -screen 0 1280x1024x24 -nolisten tcp > /out/xvfb.log 2>&1 &\nsleep 2\n'
              f'DISPLAY=:99 ./smoke-runner {runner_args} > /out/runner.log 2>&1; echo "exit=$?" >> /out/runner.log\n'
              'cp smoke-*.log smoke-report.txt /out/ 2>/dev/null || true\n')
    platform_args = ['--platform', platform[0]] if platform else []
    result = subprocess.run(['docker', 'run', '--rm', *platform_args, '-v', f'{out.resolve()}:/out', image,
                             'bash', '-c', script],
                            capture_output=True, text=True)
    (out / 'docker.log').write_text(result.stdout + result.stderr, encoding='utf-8')
    extra = ' plus ' + ', '.join(host['packages']) if host.get('packages') else ''
    return (f'container {image}{extra}',
            'suite unpacked in a stock container and checked by SHA256; smoke-runner under Xvfb')


def run_qemu(host, suite, out, runner_args):
    image, family = QEMU[host['distro']]
    tools = 'longreach-run-qemu'
    subprocess.run(['docker', 'build', '-q', '-t', tools, str(Path(__file__).with_name('qemu'))],
                   check=True, capture_output=True)
    data, _ = pack(suite)
    (out / 'suite.tar.gz').write_bytes(data)
    (out / 'setup.sh').write_text(QEMU_SETUP[family], encoding='utf-8', newline='\n')
    (out / 'runner-args').write_text(runner_args + '\n', encoding='utf-8', newline='\n')
    container = subprocess.run(['docker', 'create', image], check=True, capture_output=True, text=True).stdout.strip()
    try:
        # The image's file system goes straight into the tools container.
        export = subprocess.Popen(['docker', 'export', container], stdout=subprocess.PIPE)
        result = subprocess.run(['docker', 'run', '--rm', '-i', '-v', f'{out.resolve()}:/out', tools,
                                 'bash', '/opt/qemu/boot.sh'], stdin=export.stdout, capture_output=True, text=True)
        export.stdout.close()
        export.wait()
    finally:
        subprocess.run(['docker', 'rm', container], capture_output=True)
    (out / 'docker.log').write_text(result.stdout + result.stderr, encoding='utf-8')
    for name in ('suite.tar.gz', 'runner-args'):
        (out / name).unlink(missing_ok=True)
    return (f'QEMU, {image} userland under a current kernel',
            'suite unpacked in the guest and checked by SHA256; smoke-runner under Xvfb')


def run_ssh(host, suite, out, runner_args):
    ssh = ['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=20', '-o', 'ServerAliveInterval=30',
           *host.get('ssh_options', []), host['target']]
    data, _ = pack(suite)
    directory = host.get('dir', '/tmp/qtkit-run')
    subprocess.run(ssh + [f'rm -rf {directory} && mkdir -p {directory} && cd {directory} && tar -xzf - && '
                          '(sha256sum -c SHA256SUMS 2>/dev/null || shasum -a 256 -c SHA256SUMS) > checksums.log 2>&1 && '
                          'chmod -R u+x .'], input=data, check=True)
    body = (MACOS_RUN if host.get('os') == 'macos' else LINUX_RUN).replace('{args}', runner_args)
    subprocess.run(ssh + [f'cd {directory} && sh -s'], input=body.encode(), check=True)
    logs = subprocess.run(ssh + [f'cd {directory} && tar -czf - *.log *.txt'], capture_output=True, check=True).stdout
    with tarfile.open(fileobj=io.BytesIO(logs), mode='r:gz') as tar:
        tar.extractall(out, filter='data')
    return host.get('description', host['target']), 'suite copied over SSH and checked by SHA256; smoke-runner over SSH'


def vmrun(host, *args, check=True):
    tool = host.get('vmrun', r'C:\Program Files\VMware\VMware Workstation\vmrun.exe')
    cmd = [tool, '-T', 'ws', '-gu', host['user'], '-gp', host['_password'], *args]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if check and result.returncode != 0:
        raise SystemExit(f'vmrun {args[0]} failed: {result.stdout.strip()} {result.stderr.strip()}')
    return result


def run_vmware(host, suite, out, runner_args):
    host['_password'] = password(host)
    vmx = host['vmx']
    if host.get('os') == 'windows':
        directory = host.get('dir', r'C:\qtkit-run')
        cmd = host.get('cmd', r'C:\WINDOWS\system32\cmd.exe')
        vmrun(host, 'createDirectoryInGuest', vmx, directory, check=False)
        for path in suite_files(suite):
            if path.is_file():
                vmrun(host, 'copyFileFromHostToGuest', vmx, str(path), f'{directory}\\{path.name}')
        if host.get('direct'):
            # Windows 9x has COMMAND.COM (no && or cd /d), and NT 4's Tools
            # return early from cmd /c: start the runner itself, which writes
            # smoke-report.txt next to its executable.
            vmrun(host, 'runProgramInGuest', vmx, f'{directory}\\smoke-runner.exe', *runner_args.split(),
                  check=False)  # a failed application is a non-zero exit, not a vmrun error
        else:
            vmrun(host, 'runProgramInGuest', vmx, '-interactive', cmd,
                  f'/c cd /d {directory} && smoke-runner.exe {runner_args} > runner.log 2>&1', check=False)
        for name in ('smoke-report.txt', 'runner.log'):
            vmrun(host, 'copyFileFromGuestToHost', vmx, f'{directory}\\{name}', str(out / name), check=False)
        return host.get('description', vmx), 'suite copied with vmrun; smoke-runner.exe run in the logged-in session'
    data, _ = pack(suite)
    directory = host.get('dir', '/tmp/qtkit-run')
    with tempfile.TemporaryDirectory() as tmp:
        archive = Path(tmp) / 'suite.tar.gz'
        archive.write_bytes(data)
        vmrun(host, 'runScriptInGuest', vmx, '/bin/sh', f'rm -rf {directory} && mkdir -p {directory}')
        vmrun(host, 'copyFileFromHostToGuest', vmx, str(archive), f'{directory}/suite.tar.gz')
    vmrun(host, 'runScriptInGuest', vmx, '/bin/sh',
          f'cd {directory} && tar -xzf suite.tar.gz && rm suite.tar.gz && sha256sum -c SHA256SUMS > checksums.log 2>&1; chmod -R u+x .')
    vmrun(host, 'runScriptInGuest', vmx, '/bin/sh', f'cd {directory} && ' + LINUX_RUN.replace('{args}', runner_args), check=False)
    vmrun(host, 'runScriptInGuest', vmx, '/bin/sh', f'cd {directory} && ls *.log *.txt > files.lst')
    vmrun(host, 'copyFileFromGuestToHost', vmx, f'{directory}/files.lst', str(out / 'files.lst'))
    for name in (out / 'files.lst').read_text().split():
        vmrun(host, 'copyFileFromGuestToHost', vmx, f'{directory}/{name}', str(out / name), check=False)
    return host.get('description', vmx), 'suite copied with vmrun and checked by SHA256; smoke-runner on the logged-in X session'


def vbox(host, *args, check=True):
    cmd = ['VBoxManage', 'guestcontrol', host['vm'], *args, '--username', host['user'], '--password', host['_password']]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if check and result.returncode != 0:
        raise SystemExit(f'VBoxManage {args[0]} failed: {result.stderr.strip()}')
    return result


def run_virtualbox(host, suite, out, runner_args):
    host['_password'] = password(host)
    directory = host.get('dir', '/tmp/qtkit-run')
    data, _ = pack(suite)
    with tempfile.TemporaryDirectory() as tmp:
        archive = Path(tmp) / 'suite.tar.gz'
        archive.write_bytes(data)
        vbox(host, 'run', '--exe', '/bin/sh', '--', '-c', f'rm -rf {directory} && mkdir -p {directory}')
        vbox(host, 'copyto', str(archive), f'{directory}/suite.tar.gz')
    vbox(host, 'run', '--exe', '/bin/sh', '--', '-c',
         f'cd {directory} && tar -xzf suite.tar.gz && sha256sum -c SHA256SUMS > checksums.log 2>&1; chmod -R u+x . && '
         + LINUX_RUN.replace('{args}', runner_args), check=False)
    for name in ('smoke-report.txt', 'runner.log', 'system.txt', 'checksums.log'):
        vbox(host, 'copyfrom', f'{directory}/{name}', str(out / name), check=False)
    return host.get('description', host['vm']), 'suite copied with VBoxManage guestcontrol; smoke-runner on the X session'


def run_local(host, suite, out, runner_args):
    """The suite on this machine, in a copy under the log directory."""
    data, _ = pack(suite)
    work = out / 'suite'
    work.mkdir()
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as tar:
        tar.extractall(work, filter='data')
    runner = work / ('smoke-runner.exe' if os.name == 'nt' else 'smoke-runner')
    with open(out / 'runner.log', 'w', encoding='utf-8', errors='replace') as log:
        subprocess.run([str(runner), *runner_args.split()], cwd=work, stdout=log, stderr=subprocess.STDOUT)
    for path in work.glob('smoke-*'):
        if path.suffix in ('.txt', '.log'):
            shutil.copy2(path, out / path.name)
    if os.name == 'nt':
        info = subprocess.run(['cmd', '/c', 'ver'], capture_output=True, text=True).stdout.strip()
    else:
        info = subprocess.run(['uname', '-a'], capture_output=True, text=True).stdout.strip()
    (out / 'system.txt').write_text(info + '\n', encoding='utf-8')
    return f'this machine ({platform.platform()})', 'suite unpacked locally and smoke-runner run in the current session'


BACKENDS = {'docker': run_docker, 'qemu': run_qemu, 'ssh': run_ssh, 'vmware': run_vmware, 'virtualbox': run_virtualbox,
            'local': run_local}


def result(out, suite, sums, target, guest, method):
    report = out / 'smoke-report.txt'
    text = report.read_text(errors='replace') if report.is_file() else ''
    apps = [{'application': m.group(2), 'passed': int(m.group(3)), 'failed': int(m.group(4)),
             'skipped': int(m.group(5) or 0)}
            for m in re.finditer(r'^(PASS|FAIL)\s+(\S+)\s+---- [^\n]+?: (\d+) passed, (\d+) failed(?:, (\d+) skipped)? ----',
                                 text, re.M)]
    total = re.search(r'^(\d+) passed, (\d+) failed, (\d+) not built', text, re.M)
    summary = {'apps_passed': int(total.group(1)) if total else 0,
               'apps_failed': int(total.group(2)) if total else 0,
               'checks_passed': sum(a['passed'] for a in apps),
               'checks_failed': sum(a['failed'] for a in apps),
               'checks_skipped': sum(a['skipped'] for a in apps)}
    system = (out / 'system.txt').read_text(errors='replace').strip() if (out / 'system.txt').is_file() else ''
    ok = total is not None and summary['apps_failed'] == 0 and summary['checks_failed'] == 0 and summary['apps_passed'] > 0
    return {'schema_version': 1, 'date': datetime.date.today().isoformat(), 'target': target,
            'status': 'PASS' if ok else 'FAIL', 'image': suite.name.removeprefix('tests-'),
            'guest': {'os': system.splitlines()[0] if system else '', 'system': system, 'vm': guest, 'method': method},
            'summary': summary, 'applications': apps,
            'executables_sha256': dict(sorted((name, digest) for digest, name in
                                              (line.split() for line in sums.splitlines())))}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--suite', type=Path, required=True)
    parser.add_argument('--host', required=True)
    parser.add_argument('--out', type=Path, help='new directory for the logs (default build/runs/<suite>__<host>)')
    parser.add_argument('--json', type=Path, help='write the runtime result here as well')
    parser.add_argument('--target', default='', help='what was run, for the result (default: the suite name)')
    parser.add_argument('--runner-args', default='--timeout=900')
    parser.add_argument('--packages', default='',
                        help='docker hosts: more packages to install, space-separated (for the optional '
                             'libraries, such as GStreamer or PulseAudio, that the suite then finds)')
    args = parser.parse_args()
    if args.host == 'local':
        host = {'backend': 'local'}
    elif args.host.startswith('docker:'):
        host = {'backend': 'docker', 'distro': args.host.split(':', 1)[1], 'packages': args.packages.split()}
        if host['distro'] not in DOCKER:
            parser.error('docker hosts: ' + ', '.join(sorted(DOCKER)))
    elif args.host.startswith('qemu:'):
        host = {'backend': 'qemu', 'distro': args.host.split(':', 1)[1]}
        if host['distro'] not in QEMU:
            parser.error('qemu hosts: ' + ', '.join(sorted(QEMU)))
    else:
        hosts = json.loads(HOSTS.read_text(encoding='utf-8')) if HOSTS.is_file() else {}
        if args.host not in hosts:
            parser.error(f'{args.host} is not in {HOSTS.name} (copy hosts.example.json)')
        host = dict(hosts[args.host])
    suite = args.suite.resolve()
    out = (args.out or ROOT / 'build' / 'runs' / f'{suite.name}__{args.host.replace(":", "-")}').resolve()
    if out.exists() and any(out.iterdir()):
        parser.error(f'{out} exists; pass a new --out')
    out.mkdir(parents=True, exist_ok=True)
    _, sums = pack(suite)
    guest, method = BACKENDS[host['backend']](host, suite, out, args.runner_args)
    doc = result(out, suite, sums, args.target or suite.name, guest, method)
    text = json.dumps(doc, indent=2) + '\n'
    (out / 'result.json').write_text(text, encoding='utf-8', newline='\n')
    if args.json:
        args.json.write_text(text, encoding='utf-8', newline='\n')
    s = doc['summary']
    print(f"{doc['status']}  {suite.name} on {args.host}: apps {s['apps_passed']}/{s['apps_failed']}, "
          f"checks {s['checks_passed']}/{s['checks_failed']}/{s['checks_skipped']}  ({out})")
    sys.exit(0 if doc['status'] == 'PASS' else 1)


if __name__ == '__main__':
    main()
