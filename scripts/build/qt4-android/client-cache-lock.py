# SPDX-License-Identifier: GPL-3.0-or-later
"""Hold the retained client-volume lease for a producer and its child processes."""
import argparse
import os
from pathlib import Path
import subprocess
import sys

ROOT_ENV = 'LONGREACH_QT4_CLIENT_CACHE_ROOT'
FD_ENV = 'LONGREACH_QT4_CLIENT_CACHE_FD'
HELD_ENV = 'LONGREACH_QT4_CLIENT_CACHE_HELD'
LOCK = '.longreach-qt4-clients.lock'


class CacheLease:
    def __init__(self, root, require_inherited=False):
        self.root = Path(root).resolve()
        self.stream = None
        self.inherited = False
        lock = self.root / LOCK
        try:
            if os.name == 'posix' and os.environ.get(ROOT_ENV) == str(self.root) and os.environ.get(FD_ENV):
                descriptor = int(os.environ[FD_ENV])
                if descriptor < 3:
                    raise ValueError('Invalid client-cache descriptor')
                actual, expected = os.fstat(descriptor), lock.stat()
                if (actual.st_dev, actual.st_ino) != (expected.st_dev, expected.st_ino):
                    raise ValueError('Client-cache descriptor differs from the volume lock')
                self.stream = os.fdopen(os.dup(descriptor), 'r+b')
                self.inherited = True
            elif require_inherited:
                raise ValueError('Missing inherited client-cache lease')
            else:
                self.root.mkdir(parents=True, exist_ok=True)
                self.stream = lock.open('a+b')
                self.stream.seek(0, 2)
                if not self.stream.tell():
                    self.stream.write(b'0')
                    self.stream.flush()
                self.stream.seek(0)
            if os.name == 'nt':
                import msvcrt
                msvcrt.locking(self.stream.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(self.stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except (OSError, ValueError) as error:
            self.close()
            raise RuntimeError('Qt4 client cache is busy or its lease is invalid: ' + str(self.root)) from error

    def close(self):
        if self.stream is not None:
            # Do not flock(LOCK_UN): an inherited descriptor shares its parent's
            # open-file description. Closing releases only this process's handle.
            self.stream.close()
            self.stream = None

    def child_options(self):
        if os.name == 'posix':
            return {'pass_fds': (self.stream.fileno(),)}
        return {'creationflags': subprocess.CREATE_NO_WINDOW}

    def child_environment(self):
        env = os.environ.copy()
        env[ROOT_ENV] = str(self.root)
        env[FD_ENV] = str(self.stream.fileno())
        env[HELD_ENV] = '1'
        return env

    def __enter__(self):
        return self

    def __exit__(self, *unused):
        self.close()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--verify-inherited', action='store_true')
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    with CacheLease(args.root, require_inherited=args.verify_inherited) as lease:
        if args.verify_inherited:
            return 0
        command = args.command[1:] if args.command[:1] == ['--'] else args.command
        if not command:
            parser.error('a producer command is required')
        return subprocess.run(command, env=lease.child_environment(), **lease.child_options()).returncode


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, RuntimeError) as error:
        sys.exit(str(error))
