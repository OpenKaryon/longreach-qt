# SPDX-License-Identifier: GPL-3.0-or-later
"""Validate observed timed-sync behavior; elapsed time is not syscall tracing."""
import re

CHECKS = ('sync/mutex-timed-wakeup', 'sync/mutex-timed-timeout',
          'sync/semaphore-timed-wakeup', 'sync/semaphore-timed-timeout')
PREFIX = 'OBSERVE: '
FIELDS = re.compile(
    r'attempt=([1-3]) ready=([01]) unavailable=([01]) armed=([01]) '
    r'released_before_call=([01]) acquired=([01]) elapsed_ms=([0-9]+) '
    r'joined=([01]) verdict=(pass|retry|fail)')


def require(stdout):
    """Require one qualified final observation and contiguous bounded retries."""
    observations = {name: [] for name in CHECKS}
    passes = {name: 0 for name in CHECKS}
    for line in stdout.splitlines():
        for name in CHECKS:
            if line == 'PASS: ' + name or line.startswith('PASS: ' + name + ' - '):
                passes[name] += 1
            if not line.startswith(PREFIX + name):
                continue
            if not line.startswith(PREFIX + name + ' - '):
                raise ValueError('Malformed timed-sync observation: ' + name)
            match = FIELDS.fullmatch(line[len(PREFIX + name + ' - '):])
            if match is None:
                raise ValueError('Malformed timed-sync observation: ' + name)
            observations[name].append(match.groups())
    for name in CHECKS:
        rows = observations[name]
        timeout = name.endswith('-timeout')
        if passes[name] != 1 or not rows or len(rows) > (1 if timeout else 3):
            raise ValueError('Missing or ambiguous timed-sync evidence: ' + name)
        for index, row in enumerate(rows, 1):
            attempt, ready, unavailable, armed, released, acquired, elapsed, joined, verdict = row
            attempt, ready, unavailable, armed, released, acquired, elapsed, joined = map(
                int, (attempt, ready, unavailable, armed, released, acquired, elapsed, joined))
            if attempt != index:
                raise ValueError('Noncontiguous timed-sync attempts: ' + name)
            setup = ready and unavailable and armed and not released
            if index < len(rows):
                if (timeout or verdict != 'retry' or not joined or not ready or not acquired
                        or (setup and elapsed >= 100)):
                    raise ValueError('Invalid timed-sync retry: ' + name)
            elif (verdict != 'pass' or not joined or not setup or elapsed >= 4500
                  or (timeout and (acquired or elapsed < 150))
                  or (not timeout and (not acquired or elapsed < 100))):
                raise ValueError('Unqualified timed-sync waiting: ' + name)
    return {name: len(rows) for name, rows in observations.items()}
