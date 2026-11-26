# SPDX-License-Identifier: GPL-3.0-or-later
"""Describe the Java tools actually selected by compiler and Android launchers."""
import argparse
import hashlib
import json
import os
import platform
from pathlib import Path
import re
import shutil
import subprocess
from pathlib import PurePosixPath


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


WINDOWS_PROFILE = Path(__file__).resolve().parents[2] / 'fetch/locks/android-windows-host-tools.json'


def is_windows_host():
    return platform.system() == 'Windows'


def windows_profile():
    data = WINDOWS_PROFILE.read_bytes()
    profile = json.loads(data)
    if profile.get('schema_version') != 1 or profile.get('host') != 'windows-x64':
        raise ValueError('Invalid pinned Windows host tool profile')
    for field in ('sdk_files', 'jdk_files'):
        files = profile.get(field)
        if not isinstance(files, dict) or not files:
            raise ValueError('Empty pinned Windows tool input set: ' + field)
        for name, sha in files.items():
            path = PurePosixPath(name)
            if (not name or path.is_absolute() or '..' in path.parts or '\\' in name or
                    path.as_posix() != name or not isinstance(sha, str) or not re.fullmatch('[0-9a-f]{64}', sha)):
                raise ValueError('Invalid pinned Windows tool input')
    required_sdk = ('platform-tools/adb.exe','platform-tools/AdbWinApi.dll','platform-tools/AdbWinUsbApi.dll', 'build-tools/' + profile['build_tools_revision'] + '/aapt.exe',
                    'build-tools/' + profile['build_tools_revision'] + '/lib/d8.jar',
                    'build-tools/' + profile['build_tools_revision'] + '/lib/apksigner.jar')
    if (not all(name in profile['sdk_files'] for name in required_sdk) or
            not all(name in profile['jdk_files'] for name in ('release','bin/java.exe','bin/javac.exe','bin/keytool.exe','lib/modules'))):
        raise ValueError('Pinned Windows tool profile lacks required compiler/packaging/ADB roles')
    return profile, hashlib.sha256(data).hexdigest()


def verify_files(root, expected, kind):
    for name, sha in expected.items():
        path = root / name
        if not path.is_file() or digest(path) != sha:
            raise ValueError('Pinned Windows ' + kind + ' input differs: ' + name)


def verify_adb(adb):
    profile, profile_sha = windows_profile()
    adb = Path(adb).resolve(strict=True)
    if adb.name.lower() != 'adb.exe' or adb.parent.name.lower() != 'platform-tools':
        raise ValueError('Pinned Windows ADB must come from its platform-tools directory')
    files = {name.removeprefix('platform-tools/'): sha for name, sha in profile['sdk_files'].items()
             if name.startswith('platform-tools/')}
    verify_files(adb.parent, files, 'platform-tools')
    return {'profile_sha256':profile_sha, 'platform_tools_revision':profile['platform_tools_revision'],
            'adb_sha256':files['adb.exe']}


def executable(home, name):
    for suffix in ('.exe', ''):
        path = home / 'bin' / (name + suffix)
        if path.is_file():
            return path.resolve()
    raise ValueError('Missing Java tool: ' + str(home / 'bin' / name))


def require_home(home):
    home = Path(home).resolve(strict=True)
    executable(home, 'java')
    if not (home / 'release').is_file() or not (home / 'lib').is_dir():
        raise ValueError('Missing Java home release/lib: ' + str(home))
    return home


def settings(launcher, compiler=False):
    launcher = Path(launcher).resolve(strict=True)
    output = subprocess.check_output([str(launcher), '-J-XshowSettings:properties' if compiler else '-XshowSettings:properties', '-version'],
                                     text=True, stderr=subprocess.STDOUT, timeout=15)
    homes = re.findall(r'^\s*java\.home\s*=\s*(.+?)\s*$', output, re.M)
    if len(homes) != 1:
        raise ValueError('Cannot determine one actual java.home from: ' + str(launcher))
    return require_home(homes[0]), output


def java_toolchain(javac=None):
    selected = javac or shutil.which('javac')
    if not selected:
        raise ValueError('Missing javac on PATH')
    launcher = Path(selected).resolve(strict=True)
    home, output = settings(launcher, compiler=True)
    versions = re.findall(r'^javac\s+(.+?)\s*$', output, re.M)
    if len(versions) != 1:
        raise ValueError('Missing javac version in compiler properties output')
    return {'launcher': str(launcher), 'home': str(home), 'java': str(executable(home, 'java')),
            'javac': str(executable(home, 'javac')), 'keytool': str(executable(home, 'keytool')),
            'javac_version': 'javac ' + versions[0]}


def snapshot(android_sdk, javac=None, *, android_jar=None):
    android_sdk = Path(android_sdk).resolve(strict=True)
    compiler = java_toolchain(javac)
    roots, labels, launchers, selection = [], {}, {'javac': Path(compiler['launcher'])}, {}

    def add(home):
        home = require_home(home)
        if home not in roots:
            roots.append(home)
        return 'jdk/' + str(roots.index(home))

    selection['javac'] = add(compiler['home'])
    configured = os.environ.get('JAVA_HOME')
    if configured:
        configured_home = require_home(configured)
        selected_java = executable(configured_home, 'java')
        # Bind the configured directory and the runtime a wrapper/symlink selects.
        selection['JAVA_HOME_directory'] = add(configured_home)
        selection['JAVA_HOME_runtime'] = add(settings(selected_java)[0])
        launchers['JAVA_HOME/java'] = selected_java
    path_java = shutil.which('java')
    if path_java:
        selected_java = Path(path_java).resolve(strict=True)
        selection['PATH/java'] = add(settings(selected_java)[0])
        launchers['PATH/java'] = selected_java
    elif not configured:
        raise ValueError('Android d8/apksigner need JAVA_HOME or java on PATH')
    tools = android_sdk / 'build-tools/36.0.0'
    if not tools.is_dir():
        raise ValueError('Missing pinned-version Android build tools 36.0.0')
    tool_files = sorted(path for path in tools.rglob('*') if path.is_file())
    if not tool_files:
        raise ValueError('Empty Android build tools 36.0.0')
    for path in tool_files:
        labels['android-sdk/' + path.relative_to(android_sdk).as_posix()] = digest(path)
    if android_jar is None:
        labels['android-sdk/platforms/android-35/android.jar'] = digest(android_sdk / 'platforms/android-35/android.jar')
    else:
        labels['android-platform/android.jar'] = digest(Path(android_jar).resolve(strict=True))
    for index, home in enumerate(roots):
        paths = [home / 'release']
        for directory in ('bin', 'lib', 'conf', 'jre/bin', 'jre/lib'):
            paths += [path for path in (home / directory).rglob('*') if path.is_file() and path.name != 'src.zip']
        for path in sorted(set(paths)):
            labels[f'jdk/{index}/' + path.relative_to(home).as_posix()] = digest(path)
    for role, path in launchers.items():
        labels['launcher/' + role] = digest(path)
    result = {'schema_version': 2, 'tool_sha256': labels,
            'tool_roots': {'android-sdk': str(android_sdk), **{f'jdk/{index}': str(home) for index, home in enumerate(roots)}},
            'launcher_paths': {role: str(path) for role, path in launchers.items()},
            'java_selection': selection, 'javac_version': compiler['javac_version']}
    if is_windows_host():
        profile, profile_sha = windows_profile()
        if compiler['javac_version'] != profile['javac_version']:
            raise ValueError('Pinned Windows javac version differs')
        verify_files(android_sdk, profile['sdk_files'], 'Android SDK')
        for index, home in enumerate(roots):
            verify_files(home, profile['jdk_files'], 'JDK')
        for name in profile['sdk_files']:
            labels['android-sdk/' + name] = digest(android_sdk/name)
        result['windows_host_profile'] = {'sha256':profile_sha,
            'build_tools_revision':profile['build_tools_revision'],
            'platform_tools_revision':profile['platform_tools_revision'],
            'jdk_runtime_version':profile['jdk_runtime_version']}
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('java-home','verify-adb'))
    parser.add_argument('--javac', type=Path)
    parser.add_argument('--adb', type=Path)
    args = parser.parse_args(argv)
    if args.action == 'verify-adb':
        if args.adb is None: parser.error('verify-adb requires --adb')
        print(json.dumps(verify_adb(args.adb)))
    else:
        print(json.dumps(java_toolchain(args.javac)))


if __name__ == '__main__':
    main()
