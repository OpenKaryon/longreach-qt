#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Git hooks that keep private words out of the repository.

`install` writes three small hooks into the repository; each runs this file,
from the repository it belongs to, with the Python it was installed from:

- pre-commit: the stop words in the staged changes;
- commit-msg: the stop words in the message and the author and committer
  identities;
- pre-push: the stop words in everything the push sends.

The words are listed outside the repository (scripts/audit/stop_words.py says
where). Without a list the hooks say in capitals that the stop words were not
checked, and go on. `git commit --no-verify` and `git push --no-verify` skip
them.

    python scripts/audit/git_hooks.py install [REPO] [--force]
    python scripts/audit/git_hooks.py uninstall [REPO]
"""

from __future__ import annotations

import argparse
from pathlib import Path
import subprocess
import sys

HOOKS = ("pre-commit", "commit-msg", "pre-push")
MARKER = "# scripts/audit/git_hooks.py"
HERE = Path(__file__).resolve().parent


def _git(repo: Path, *args: str) -> str:
    return subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, check=True).stdout.strip()


def hooks_folder(repo: Path) -> Path:
    folder = Path(_git(repo, "rev-parse", "--git-path", "hooks"))
    return folder if folder.is_absolute() else (repo / folder).resolve()


def script(hook: str) -> str:
    python = Path(sys.executable).as_posix()
    return f"""#!/bin/sh
{MARKER}: reinstall with python scripts/audit/git_hooks.py install
hooks="$(git rev-parse --show-toplevel)/scripts/audit/git_hooks.py"
if [ ! -f "{python}" ] || [ ! -f "$hooks" ]; then
    echo "STOP-WORD HOOKS NOT RUN: {python} or $hooks is missing; reinstall them" >&2
    exit 0
fi
exec "{python}" "$hooks" run {hook} "$@"
"""


def install(repo: Path, force: bool = False) -> list[Path]:
    folder = hooks_folder(repo)
    folder.mkdir(parents=True, exist_ok=True)
    written = []
    for hook in HOOKS:
        path = folder / hook
        if path.exists() and MARKER not in path.read_text(encoding="utf-8", errors="replace") and not force:
            raise SystemExit(f"{path} is not ours; move it away or pass --force")
        path.write_text(script(hook), encoding="utf-8", newline="\n")
        path.chmod(0o755)
        written.append(path)
    return written


def uninstall(repo: Path) -> list[Path]:
    removed = []
    for hook in HOOKS:
        path = hooks_folder(repo) / hook
        if path.exists() and MARKER in path.read_text(encoding="utf-8", errors="replace"):
            path.unlink()
            removed.append(path)
    return removed


def _stop_words(*args: str, stdin: str | None = None) -> int:
    return subprocess.run([sys.executable, str(HERE / "stop_words.py"), *args], input=stdin, text=True).returncode


def run(hook: str, args: list[str], repo: Path) -> int:
    if hook == "pre-commit":
        return _stop_words("staged", str(repo))
    if hook == "commit-msg":
        return _stop_words("message", args[0], str(repo))
    if hook == "pre-push":
        return _stop_words("push", args[0], str(repo), stdin=sys.stdin.read())
    raise SystemExit(f"unknown hook {hook}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="git_hooks", description=__doc__.split("\n", 1)[0])
    commands = parser.add_subparsers(dest="command", required=True)
    installing = commands.add_parser("install")
    installing.add_argument("repo", nargs="?", type=Path, default=Path("."))
    installing.add_argument("--force", action="store_true", help="replace hooks that are not ours")
    commands.add_parser("uninstall").add_argument("repo", nargs="?", type=Path, default=Path("."))
    running = commands.add_parser("run")
    running.add_argument("hook", choices=HOOKS)
    running.add_argument("args", nargs="*")
    args = parser.parse_args(argv)

    if args.command == "run":
        return run(args.hook, args.args, Path(_git(Path("."), "rev-parse", "--show-toplevel")))
    repo = Path(_git(args.repo, "rev-parse", "--show-toplevel"))
    if args.command == "install":
        for path in install(repo, args.force):
            print(f"installed {path}")
        sys.path.insert(0, str(HERE))
        import stop_words
        if stop_words.locate(repo) is None:
            print(stop_words.not_performed(repo), file=sys.stderr)
    else:
        for path in uninstall(repo):
            print(f"removed {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
