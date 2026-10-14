#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Run already-built Linux suites on current distributions (forward check).

Each pair of suite and distribution runs in a fresh container that installs
only that distribution's own packages: the X11/OpenGL/font libraries the
suite links to, and Xvfb. Nothing from the build images is reused. The check
fails a pair when ldd reports a missing library or smoke-runner reports a
failure. Logs land in artifacts/runtime-linux-forward/<date>/ and a summary in
docs/results/linux-forward-<date>.json.
"""
import argparse
import concurrent.futures
import datetime
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]

# suite: (artifact directory, architecture, X client kind, year of its floor)
SUITES = {
    'qt4-linux-i386': ('artifacts/tests-qt4-linux-i386', 'i386', 'xlib', 2005),
    'qt4-linux-amd64': ('artifacts/tests-qt4-linux-amd64', 'amd64', 'xlib', 2005),
    'qt5-linux-amd64': ('artifacts/tests-qt5-linux-amd64', 'amd64', 'xlib', 2010),
    'qt6-linux-amd64': ('artifacts/tests-qt6-linux-amd64', 'amd64', 'xcb', 2014),
}

# distro: (image, package family, release year, role)
DISTROS = {
    'centos-7': ('centos:7.9.2009', 'rhel', 2014, 'baseline'),
    'ubuntu-16.04': ('ubuntu:16.04', 'debian', 2016, 'baseline'),
    'ubuntu-18.04': ('ubuntu:18.04', 'debian', 2018, 'baseline'),
    'ubuntu-24.04': ('ubuntu:24.04', 'debian', 2024, 'current'),
    'debian-13': ('debian:trixie', 'debian', 2025, 'current'),
    'fedora-latest': ('fedora:latest', 'fedora', 2026, 'current'),
    'arch-latest': ('archlinux:latest', 'arch', 2026, 'current'),
}

PACKAGES = {
    ('debian', 'xlib'): 'libgl1 libx11-6 libxext6 libxrender1 libsm6 libice6 libfontconfig1 libfreetype6',
    ('debian', 'xcb'): ('libgl1 libopengl0 libx11-6 libx11-xcb1 libxcb1 libxcb-glx0 libxcb-cursor0 '
                        'libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-randr0 libxcb-render-util0 '
                        'libxcb-render0 libxcb-shape0 libxcb-shm0 libxcb-sync1 libxcb-xfixes0 libxcb-xkb1 '
                        'libxkbcommon0 libxkbcommon-x11-0'),
    ('fedora', 'xlib'): 'mesa-libGL libX11 libXext libXrender libSM libICE fontconfig freetype',
    ('rhel', 'xlib'): 'mesa-libGL libX11 libXext libXrender libSM libICE fontconfig freetype',
    ('fedora', 'xcb'): ('mesa-libGL libglvnd-opengl libX11 libX11-xcb libxcb xcb-util-cursor xcb-util-image '
                        'xcb-util-keysyms xcb-util-renderutil xcb-util-wm libxkbcommon libxkbcommon-x11'),
    ('arch', 'xlib'): 'mesa libglvnd libx11 libxext libxrender libsm libice fontconfig freetype2',
    ('arch', 'xcb'): ('mesa libglvnd libx11 libxcb xcb-util-cursor xcb-util-image xcb-util-keysyms '
                      'xcb-util-renderutil xcb-util-wm libxkbcommon libxkbcommon-x11'),
}


def install_command(family, arch, kind):
    packages = PACKAGES[(family, kind)]
    if arch == 'i386':
        suffix = ':i386' if family == 'debian' else '.i686'
        packages = ' '.join(p + suffix for p in ('libc6 ' + packages if family == 'debian'
                                                 else 'glibc ' + packages).split())
    if family == 'debian':
        multiarch = 'dpkg --add-architecture i386 && ' if arch == 'i386' else ''
        return (f'{multiarch}apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq '
                f'--no-install-recommends {packages} fonts-dejavu-core xvfb xauth ca-certificates >/dev/null')
    if family == 'fedora':
        return f'dnf install -y -q {packages} dejavu-sans-fonts xorg-x11-server-Xvfb >/dev/null'
    if family == 'rhel':
        # CentOS 7 is end-of-life; its packages stay on vault.centos.org.
        return ("sed -i -e 's|^mirrorlist=|#mirrorlist=|' "
                "-e 's|^#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|' "
                "/etc/yum.repos.d/CentOS-*.repo && "
                f'yum install -y -q {packages} dejavu-sans-fonts xorg-x11-server-Xvfb >/dev/null')
    return f'pacman -Sy --noconfirm --needed {packages} ttf-dejavu xorg-server-xvfb >/dev/null'


GUEST = r'''
set -u
{install} || {{ echo "INSTALL FAILED"; exit 3; }}
# A container image may ship an empty machine-id; libdbus aborts on one, a
# real installation always has it.
[ -s /etc/machine-id ] || tr -d - < /proc/sys/kernel/random/uuid > /etc/machine-id
cat /etc/os-release > /out/os-release
ldd --version 2>&1 | head -1 > /out/libc.txt
mkdir /tmp/run && cp -a /in/. /tmp/run/ && cd /tmp/run
: > /out/ldd-missing.txt
for f in *; do
    if [ -f "$f" ] && head -c4 "$f" | grep -q ELF; then
        ldd "./$f" 2>&1 | grep 'not found' | sed "s|^|$f: |" >> /out/ldd-missing.txt
    fi
done
# By default nothing points Qt at the fonts, as on an ordinary desktop.
# --set-fontdir points QT_QPA_FONTDIR at the distribution's DejaVu directory,
# as the Bionic runtime proof did, to compare.
if [ "${{SMOKE_SET_FONTDIR:-0}}" = 1 ]; then
    fontdir=$(dirname "$(find /usr/share/fonts -name DejaVuSans.ttf | head -1)")
    export QT_QPA_FONTDIR="$fontdir"
fi
echo "QT_QPA_FONTDIR=${{QT_QPA_FONTDIR:-unset}}" > /out/fontdir.txt
Xvfb :99 -screen 0 1280x1024x24 -nolisten tcp >/out/xvfb.log 2>&1 &
sleep 2
DISPLAY=:99 timeout 3600 ./smoke-runner > /out/runner.log 2>&1
echo "runner exit=$?" >> /out/runner.log
cp smoke-report.txt /out/ 2>/dev/null || true
'''


def run_pair(suite, distro, out_root, set_fontdir=False):
    source, arch, kind, _ = SUITES[suite]
    image, family, _, _ = DISTROS[distro]
    out = out_root / f'{suite}__{distro}'
    out.mkdir(parents=True, exist_ok=True)
    script = GUEST.format(install=install_command(family, arch, kind))
    command = ['docker', 'run', '--rm', '-e', f'SMOKE_SET_FONTDIR={int(set_fontdir)}',
               '-v', f'{(ROOT / source).resolve()}:/in:ro',
               '-v', f'{out.resolve()}:/out', image, 'bash', '-c', script]
    if family == 'arch':
        command[2:2] = ['--platform', 'linux/amd64']
    result = subprocess.run(command, capture_output=True, text=True)
    (out / 'docker.log').write_text(result.stdout + result.stderr, encoding='utf-8')
    return summarize(suite, distro, out, result.returncode)


def summarize(suite, distro, out, docker_exit):
    row = {'suite': suite, 'distro': distro, 'role': DISTROS[distro][3], 'docker_exit': docker_exit}
    release = out / 'os-release'
    if release.exists():
        fields = dict(line.split('=', 1) for line in release.read_text().splitlines() if '=' in line)
        row['os'] = fields.get('PRETTY_NAME', '').strip('"')
    libc = out / 'libc.txt'
    if libc.exists():
        row['libc'] = libc.read_text().strip()
    missing = out / 'ldd-missing.txt'
    row['ldd_missing'] = missing.read_text().splitlines() if missing.exists() else None
    report = out / 'smoke-report.txt'
    if report.exists():
        text = report.read_text(errors='replace')
        total = re.search(r'^(\d+) passed, (\d+) failed, (\d+) not built', text, re.M)
        if total:
            row['apps_passed'], row['apps_failed'], row['apps_not_built'] = map(int, total.groups())
        checks = [tuple(map(int, m.groups(default='0'))) for m in
                  # Only the runner's one summary line per application; each
                  # footer also appears in that application's own section.
                  re.finditer(r'^(?:PASS|FAIL)\s+\S+\s+---- [^\n]+?: (\d+) passed, (\d+) failed'
                              r'(?:, (\d+) skipped)? ----', text, re.M)]
        row['checks_passed'] = sum(c[0] for c in checks)
        row['checks_failed'] = sum(c[1] for c in checks)
        row['checks_skipped'] = sum(c[2] for c in checks)
        row['failed_apps'] = re.findall(r'^(?:FAIL|CRASH|TIMEOUT)\s+(\S+)', text, re.M)
    row['status'] = ('PASS' if docker_exit == 0 and row.get('apps_failed') == 0 and row.get('apps_passed')
                     and not row['ldd_missing'] else 'FAIL')
    return row


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--suite', action='append', choices=sorted(SUITES))
    parser.add_argument('--distro', action='append', choices=sorted(DISTROS))
    parser.add_argument('--jobs', type=int, default=3)
    parser.add_argument('--set-fontdir', action='store_true',
                        help='point QT_QPA_FONTDIR at the distribution DejaVu fonts')
    args = parser.parse_args()
    date = datetime.date.today().strftime('%Y%m%d')
    out_root = ROOT / 'artifacts/runtime-linux-forward' / date
    pairs = [(s, d) for s in (args.suite or sorted(SUITES)) for d in (args.distro or sorted(DISTROS))
             if not (SUITES[s][1] == 'i386' and DISTROS[d][1] == 'arch')
             and DISTROS[d][2] >= SUITES[s][3]]
    with concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
        rows = list(pool.map(lambda p: run_pair(*p, out_root, args.set_fontdir), pairs))
    for row in rows:
        print(f"{row['status']:4}  {row['suite']:20} {row['distro']:14} {row.get('os', '?'):32} "
              f"apps {row.get('apps_passed')}/{row.get('apps_failed')}  checks "
              f"{row.get('checks_passed')}/{row.get('checks_failed')}/{row.get('checks_skipped')}  "
              f"ldd-missing {len(row['ldd_missing'] or [])}")
    summary = ROOT / f'docs/results/linux-forward-{date}.json'
    summary.write_text(json.dumps({'date': date, 'evidence': out_root.relative_to(ROOT).as_posix(),
                                   'runs': rows}, indent=2) + '\n', encoding='utf-8')
    print('summary:', summary.relative_to(ROOT))
    raise SystemExit(0 if all(r['status'] == 'PASS' for r in rows) else 1)


if __name__ == '__main__':
    main()
