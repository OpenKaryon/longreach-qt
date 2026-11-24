# SPDX-License-Identifier: GPL-3.0-or-later
"""Prepare the two pinned API4 archives and verify retained extraction receipts."""
import argparse
import importlib.util
from pathlib import Path, PurePosixPath
import re
import sys
import zipfile


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


HERE = Path(__file__).resolve().parent
artifacts = load('api4_media_artifacts', HERE / 'donut-artifacts.py')
common = artifacts.common
extractor = load('api4_media_extractor', HERE.parent / 'qt6-android/prepare-emulator.py')
PINS = {
    'android-1.6_r03-linux.zip': 'a8c4e3b32269c6b04c2adeabd112fce42f292dab1a40ef3b08ea7d4212be0df4',
    'tools_r24.4.1-windows.zip': '74fe511d80d28678f2250f89b63d0d8e5ba80428cb2345279fa019183fa0476f',
}
LAYOUT = {
    'android-1.6_r03-linux.zip': ('android-1.6_r03-linux', ('android-1.6_r03-linux/android.jar',
        *('android-1.6_r03-linux/images/' + name for name in ('kernel-qemu', 'ramdisk.img', 'system.img', 'userdata.img')))),
    'tools_r24.4.1-windows.zip': ('tools', ('tools/emulator-arm.exe',)),
}


def destination_root(destination):
    # Keep the same output/inputs contract as the original API4 entry points.
    if destination.exists():
        artifacts.safe(destination)
    destination = destination.resolve()
    if destination.name != 'inputs':
        raise ValueError('API4 media destination must be the artifact root inputs directory')
    return destination.parent


def safe_tree(base):
    if base.exists():
        artifacts.safe(base)
        for path in base.rglob('*'):
            artifacts.safe(path)


def extract(archive, destination, member, expected_sha):
    if archive.name not in PINS or expected_sha != PINS[archive.name]:
        raise ValueError('Unpinned API4 media archive selection')
    root_name, required = LAYOUT[archive.name]
    if member not in required:
        raise ValueError('Unexpected API4 media member')
    if common.digest(archive) != expected_sha:
        raise ValueError('SHA256 mismatch for API4 media archive: ' + archive.name)
    # Before the shared extractor moves a previous tree, verify that the resolved
    # source and destination stay inside this explicitly selected inputs root.
    if destination.exists():
        artifacts.safe(destination)
    destination.mkdir(parents=True, exist_ok=True)
    current = destination / root_name
    safe_tree(current)
    if current.exists() and current.resolve().parent != destination.resolve():
        raise ValueError('Unexpected API4 extraction move source')
    with zipfile.ZipFile(archive) as package:
        names = [item.filename for item in package.infolist() if not item.is_dir()]
        if any(PurePosixPath(name).parts[0] != root_name for name in names):
            raise ValueError('API4 archive has an unexpected extraction root')
    common.invalidate_results(destination.parent)
    result = extractor.prepare_archive(archive, expected_sha, destination, required)
    verify_archive(destination, archive.name)
    return result


def verify_archive(destination, name):
    root_name, required = LAYOUT[name]
    path = destination / (name + '.extracted.json')
    artifacts.safe(path)
    receipt = common.read_json(path)
    files = receipt.get('files', {})
    if (receipt.get('schema_version') != 1 or receipt.get('archive_sha256') != PINS[name] or
            receipt.get('extractor_sha256') != common.digest(Path(extractor.__file__)) or
            not isinstance(files, dict) or not set(required).issubset(files)):
        raise ValueError('Missing or mismatched prepared API4 extraction receipt')
    for relative, sha in files.items():
        parts = PurePosixPath(relative).parts
        if (not parts or parts[0] != root_name or '\\' in relative or ':' in relative or '..' in parts or
                not re.fullmatch(r'[0-9a-f]{64}', sha)):
            raise ValueError('Invalid prepared API4 file inventory')
    safe_tree(destination / root_name)
    if extractor.inventory(destination, [root_name]) != set(files) or not extractor.files_match(destination, files):
        raise ValueError('Prepared API4 file bytes or inventory changed')
    return files


def verify(destination):
    destination_root(destination)
    files, receipts = {}, {}
    for name in PINS:
        verified = verify_archive(destination, name)
        files.update({'inputs/' + relative: sha for relative, sha in verified.items()})
        receipts[name] = common.digest(destination / (name + '.extracted.json'))
    return {'schema_version': 2, 'archives': dict(PINS),
            'preparer_sha256': common.digest(Path(__file__)),
            'extractor_sha256': common.digest(Path(extractor.__file__)),
            'extraction_receipts': receipts, 'files': files}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('extract', 'verify'))
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--archive', type=Path)
    parser.add_argument('--member')
    parser.add_argument('--sha256')
    parser.add_argument('--artifact-lease-held', action='store_true', help='internal: caller owns the artifact lease')
    args = parser.parse_args(argv)
    root = destination_root(args.destination)
    root.mkdir(parents=True, exist_ok=True)
    with common.artifact_lease(root, args.artifact_lease_held):
        if args.action == 'extract':
            if not args.archive or not args.member or not args.sha256:
                parser.error('extract requires --archive, --member and --sha256')
            extract(args.archive.resolve(), args.destination.resolve(), args.member, args.sha256)
        else:
            verify(args.destination.resolve())
    print('API4 prepared archive ' + args.action + ': PASS')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, RuntimeError, zipfile.BadZipFile) as error:
        sys.exit('API4 prepared archive validation failed: ' + str(error))
