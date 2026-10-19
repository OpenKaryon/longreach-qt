#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Keep the OpenKaryonLab copies of what the build downloads (sources.json).

    python scripts/fetch/mirror.py check               the list against the build's pins
    python scripts/fetch/mirror.py check --online      ... and the copies hold every pin
    python scripts/fetch/mirror.py repos   [--apply]   Git repositories, with a tag per pin
    python scripts/fetch/mirror.py archives [--apply]  source archives, as release assets
    python scripts/fetch/mirror.py images  [--apply]   base images, to ghcr.io by digest

Without --apply each command prints what it would do. With it, it needs gh
logged in, as one of the accounts sources.json lists as publishers, with
rights on the organisation (and, for images, `docker login ghcr.io` as the
same account): whatever is published shows that account. Tags are made as
this clone's own git identity, never the global one. Nothing is deleted or
rewritten: a repository gets the upstream
branches and tags it does not have, plus longreach/<commit> tags that keep
every pinned commit reachable however upstream moves; an archive is
uploaded only when its SHA256 matches the pin.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCES = json.loads((ROOT / 'scripts/fetch/sources.json').read_text(encoding='utf-8'))
LAB = SOURCES['lab']
RELEASE_REPO = f'{LAB}/longreach-qt-sources'
RELEASE_TAG = 'sources'
# Push with gh's token, the publisher checked by publisher(), not whatever
# account the system credential helper remembers.
AS_PUBLISHER = ['-c', 'credential.helper=', '-c', 'credential.helper=!gh auth git-credential']
# The first commit of the archives repository: a release needs one to tag.
SOURCES_README = '''# longreach-qt-sources

The source archives and tools
[longreach-qt](https://github.com/OpenKaryon/longreach-qt) builds from, as the
assets of the release [`sources`](../../releases/tag/sources). Each file is the
upstream one, byte for byte. Where it came from, its licence and the SHA256 the
build checks it against are listed in longreach-qt's
[`scripts/fetch/sources.json`](https://github.com/OpenKaryon/longreach-qt/blob/main/scripts/fetch/sources.json);
`scripts/fetch/mirror.py` there fills this release.
'''
# Where the build reads its pins.
PIN_FILES = ['Makefile', 'mk/*.mk', 'docker/**/Dockerfile', 'scripts/build/**/*.sh', 'scripts/build/**/*.py',
             'scripts/fetch/*.py', 'scripts/fetch/*.sh', 'scripts/run/**/Dockerfile']


def identity() -> list[str]:
    """`git -c` options for this clone's local author: annotated tags carry it."""
    options = []
    for key in ('user.name', 'user.email'):
        value = subprocess.run(['git', '-C', str(ROOT), 'config', '--local', key],
                               capture_output=True, text=True).stdout.strip()
        if not value:
            raise SystemExit(f'{key} is not set in this clone (git config --local {key} ...)')
        options += ['-c', f'{key}={value}']
    return options


def publisher(apply: bool) -> None:
    """Refuse to publish from an account sources.json does not name."""
    if not apply:
        return
    login = subprocess.run(['gh', 'api', 'user', '--jq', '.login'], capture_output=True, text=True).stdout.strip()
    if login not in SOURCES['publishers']:
        raise SystemExit('gh is not logged in as a publisher listed in sources.json; '
                         'switch with gh auth switch, or log in as one')


def run(command: list[str], apply: bool, check: bool = True, **kw) -> subprocess.CompletedProcess | None:
    print(('$ ' if apply else 'would run: ') + ' '.join(shlex.quote(c) for c in command), flush=True)
    if apply:
        return subprocess.run(command, check=check, **kw)
    return None


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b''):
            digest.update(chunk)
    return digest.hexdigest()


def pinned_text() -> str:
    return '\n'.join(p.read_text(encoding='utf-8', errors='replace')
                     for pattern in PIN_FILES for p in sorted(ROOT.glob(pattern)) if p.is_file())


def online_problems() -> list[str]:
    """What the build would not find in the copies: it takes them first."""
    problems = []
    present = release_assets()
    for archive in SOURCES['archives']:
        if archive['file'] not in present:
            problems.append(f"{archive['file']}: not in the {RELEASE_TAG} release of {RELEASE_REPO}")
        elif not present[archive['file']]:
            problems.append(f"{archive['file']}: GitHub reports no SHA256 for the copy; "
                            'download it and compare, or upload it again')
        elif present[archive['file']] != archive['sha256']:
            problems.append(f"{archive['file']}: the copy's SHA256 differs from the pin")
    for repository in SOURCES['repositories']:
        url = f"https://github.com/{LAB}/{repository['name']}.git"
        listing = subprocess.run(['git', 'ls-remote', url, 'refs/tags/longreach/*'],
                                 capture_output=True, text=True, env=dict(os.environ, GIT_TERMINAL_PROMPT='0'))
        # An annotated tag's line ending in ^{} names the commit it tags.
        tagged = {line.split()[0] for line in listing.stdout.splitlines() if line.endswith('^{}')}
        for commit in repository['pins']:
            if commit not in tagged:
                problems.append(f"{repository['name']} {commit[:12]}: no longreach/ tag for it in {url}")
    for image in SOURCES['images']:
        ref = f"ghcr.io/{LAB.lower()}/{image['name']}:{image['tag']}@{image['digest']}"
        if subprocess.run(['docker', 'buildx', 'imagetools', 'inspect', ref], capture_output=True).returncode:
            problems.append(f'{ref}: not pullable')
    return problems


def check(args) -> int:
    """Every listed hash and commit is pinned somewhere in the build, and every
    SHA256 the build pins is either listed or explained as not copied. With
    --online, the copies hold all of it."""
    text = pinned_text()
    problems = []
    listed = {a['sha256'] for a in SOURCES['archives']}
    listed |= {n['sha256'] for n in SOURCES['not_mirrored'] if 'sha256' in n}
    listed |= {i['digest'].split(':', 1)[1] for i in SOURCES['images']}
    for archive in SOURCES['archives']:
        if archive['sha256'] not in text:
            problems.append(f"{archive['file']}: SHA256 not pinned anywhere in the build")
        local = ROOT / 'downloads' / archive['file']
        if local.is_file() and sha256(local) != archive['sha256']:
            problems.append(f"downloads/{archive['file']}: SHA256 differs from the pin")
    for repository in SOURCES['repositories']:
        for commit in repository['pins']:
            if commit not in text:
                problems.append(f"{repository['name']} {commit[:12]}: commit not pinned in the build")
    for image in SOURCES['images']:
        if f"{image['name']}:{image['tag']}@{image['digest']}" not in text:
            problems.append(f"image {image['name']}:{image['tag']}@{image['digest'][:19]}...: "
                            'not used with that tag and digest')
    # An image named by tag only, outside a FROM (docker run in make).
    for path in [ROOT / 'Makefile', *sorted(ROOT.glob('mk/*.mk'))]:
        for found in re.findall(r'\b(?:debian|ubuntu|centos):[\w.-]+(?!@sha256|[\w.-])', path.read_text(encoding='utf-8')):
            problems.append(f'{path.relative_to(ROOT).as_posix()}: {found} has no digest')
    # Every base image is pinned by digest and pulled through BASE_REGISTRY;
    # FROM a stage or an image this build made (an ARG) is fine.
    for path in sorted(p for pattern in ('docker/**/Dockerfile', 'scripts/run/**/Dockerfile')
                       for p in ROOT.glob(pattern)):
        stages = set()
        for line in path.read_text(encoding='utf-8').splitlines():
            words = line.split()
            if not words or words[0] != 'FROM':
                continue
            words = [w for w in words[1:] if not w.startswith('--')]
            source = words[0]
            if len(words) >= 3 and words[1].upper() == 'AS':
                stages.add(words[2])
            if source in stages or (source.startswith('${') and source.endswith('}')):
                continue
            if not source.startswith('${BASE_REGISTRY}/') or '@sha256:' not in source:
                problems.append(f'{path.relative_to(ROOT).as_posix()}: FROM {source} is not '
                                '${BASE_REGISTRY}/<image>@<digest>')
    # SHA256 pins in the build that this list does not know (Debian and Ubuntu
    # packages live in scripts/fetch/locks/, which is not searched).
    for found in sorted(set(re.findall(r'(?<![0-9a-f])[0-9a-f]{64}(?![0-9a-f])', text)) - listed):
        problems.append(f'pinned SHA256 {found[:12]}... is neither copied nor listed as not copied')
    if args.online:
        problems += online_problems()
    for line in problems:
        print('PROBLEM ' + line)
    print(f"{len(SOURCES['archives'])} archives, {len(SOURCES['repositories'])} repositories, "
          f"{len(SOURCES['images'])} images; {len(problems)} problems")
    return 1 if problems else 0


def repo_exists(name: str) -> bool:
    return subprocess.run(['gh', 'repo', 'view', name], capture_output=True).returncode == 0


def remote_tags(url: str) -> set[str]:
    listing = subprocess.run(['git', 'ls-remote', '--tags', url], capture_output=True, text=True,
                             env=dict(os.environ, GIT_TERMINAL_PROMPT='0'))
    return {line.split()[1].removeprefix('refs/tags/').removesuffix('^{}')
            for line in listing.stdout.splitlines() if line.strip()}


def repos(args) -> int:
    publisher(args.apply)
    tagger = identity()
    refused = []
    for repository in SOURCES['repositories']:
        target = f"{LAB}/{repository['name']}"
        print(f"== {target} <- {repository['upstream']}")
        if not repo_exists(target):
            run(['gh', 'repo', 'create', target, '--public', '--disable-issues', '--disable-wiki',
                 '--description', f"Copy of {repository['upstream']} for longreach-qt: pinned commits "
                                  f"are tagged longreach/<commit>"], args.apply)
        with tempfile.TemporaryDirectory(prefix='lab-mirror-') as scratch:
            bare = str(Path(scratch) / 'repo.git')
            run(['git', 'clone', '--bare', repository['upstream'], bare], args.apply)
            remote = f'https://github.com/{target}.git'
            # A longreach/ tag already in the copy stays as it is: made again it
            # would be a new tag object, which the push refuses.
            there = remote_tags(remote)
            for commit, why in repository['pins'].items():
                if f'longreach/{commit[:12]}' in there:
                    print(f'longreach/{commit[:12]}: already in the copy')
                    continue
                run(['git', *tagger, '-C', bare, 'tag', '-a', '-m', f'longreach-qt: {why}',
                     f'longreach/{commit[:12]}', commit], args.apply)
            # Branches and tags that are new; an existing one that moved upstream
            # is refused rather than overwritten, and reported at the end.
            for refs in ('refs/heads/*:refs/heads/*', 'refs/tags/*:refs/tags/*'):
                result = run(['git', *AS_PUBLISHER, '-C', bare, 'push', remote, refs], args.apply, check=False)
                if result is not None and result.returncode:
                    refused.append(f'{target} {refs.split(":")[0]}')
    if refused:
        print('Refused (upstream moved a ref the copy has; nothing was overwritten): ' + ', '.join(refused))
        return 1
    return 0


def release_assets() -> dict[str, str]:
    """The release's files, each with the SHA256 GitHub computed on upload ('' if none)."""
    result = subprocess.run(['gh', 'api', f'repos/{RELEASE_REPO}/releases/tags/{RELEASE_TAG}',
                             '--jq', '.assets[] | .name + " " + (.digest // "")'], capture_output=True, text=True)
    if result.returncode != 0:
        return {}
    assets = {}
    for line in result.stdout.splitlines():
        name, _, digest = line.partition(' ')
        assets[name] = digest.removeprefix('sha256:')
    return assets


def seed(apply: bool) -> None:
    """The archives repository's first commit, a README: a release needs a commit to tag."""
    with tempfile.TemporaryDirectory(prefix='lab-sources-') as scratch:
        if apply:
            Path(scratch, 'README.md').write_text(SOURCES_README, encoding='utf-8', newline='\n')
        git = ['git', *identity(), '-c', 'core.autocrlf=false', '-C', scratch]
        run(git + ['init', '-q', '-b', 'main'], apply)
        run(git + ['add', 'README.md'], apply)
        run(git + ['commit', '-q', '-m', 'What this repository holds'], apply)
        run(['git', *AS_PUBLISHER, '-C', scratch, 'push', f'https://github.com/{RELEASE_REPO}.git', 'main'], apply)


def archives(args) -> int:
    publisher(args.apply)
    sys.path.insert(0, str(ROOT / 'scripts/fetch'))
    import fetch
    if not repo_exists(RELEASE_REPO):
        run(['gh', 'repo', 'create', RELEASE_REPO, '--public', '--disable-issues', '--disable-wiki',
             '--description', 'Source archives longreach-qt builds from, pinned by SHA256'], args.apply)
        seed(args.apply)
    present = release_assets()
    if not present:
        run(['gh', 'release', 'create', RELEASE_TAG, '--repo', RELEASE_REPO, '--title', 'Sources',
             '--notes', 'Each file is the upstream one, checked against the SHA256 longreach-qt pins.'],
            args.apply)
    # The release only grows: a new version is a new file name, and the files
    # older longreach-qt tags name stay. A file whose name is there but whose
    # content is not the pin (upstream rolled it again) stops the run.
    mismatched = []
    for archive in SOURCES['archives']:
        if archive['file'] in present:
            digest = present[archive['file']]
            if not digest:
                mismatched.append(archive['file'])
                print(f"{archive['file']}: there, but GitHub reports no SHA256 for it")
            elif digest != archive['sha256']:
                mismatched.append(archive['file'])
                print(f"{archive['file']}: there, but its SHA256 is {digest}, not the pin")
            else:
                print(f"{archive['file']}: already there")
            continue
        local = ROOT / 'downloads' / archive['file']
        if not local.is_file():
            print(f"{archive['file']}: downloading from upstream first")
            if args.apply:
                # From upstream itself: the copy is what this fills.
                part = Path(fetch.download(archive['url'], str(local), [archive['url']]))
                if sha256(part) != archive['sha256']:
                    part.unlink()
                    print(f"{archive['file']}: upstream's SHA256 differs from the pin; not kept")
                    mismatched.append(archive['file'])
                    continue
                part.replace(local)
        if args.apply and sha256(local) != archive['sha256']:
            print(f"{archive['file']}: SHA256 differs from the pin; not uploaded")
            continue
        run(['gh', 'release', 'upload', RELEASE_TAG, str(local), '--repo', RELEASE_REPO], args.apply)
    if mismatched:
        print('Not matching the pins: ' + ', '.join(mismatched) + '. A pinned file keeps its name and '
              'content; give a new one, and its pin, a new name instead of replacing it.')
        return 1
    return 0


def images(args) -> int:
    publisher(args.apply)
    for image in SOURCES['images']:
        source = f"docker.io/library/{image['name']}:{image['tag']}@{image['digest']}"
        target = f"ghcr.io/{LAB.lower()}/{image['name']}:{image['tag']}"
        # imagetools copies the manifest list as it is: the digest stays the same.
        run(['docker', 'buildx', 'imagetools', 'create', '--tag', target, source], args.apply)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('check').add_argument('--online', action='store_true',
                                              help='also check that the copies hold every pin')
    for name in ('repos', 'archives', 'images'):
        commands.add_parser(name).add_argument('--apply', action='store_true', help='do it, not just print it')
    args = parser.parse_args()
    return {'check': check, 'repos': repos, 'archives': archives, 'images': images}[args.command](args)


if __name__ == '__main__':
    sys.exit(main())
