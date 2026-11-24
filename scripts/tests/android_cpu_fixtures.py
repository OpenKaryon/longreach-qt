# SPDX-License-Identifier: GPL-3.0-or-later
"""Synthetic CPU text and its actual validator report, never a guest result."""
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('fixture_guest_cpu', ROOT / 'scripts/run/android-cpu.py')
cpu = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cpu)


def capture(directory, abi, flags=None):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    if abi in cpu.REQUIRED:
        text = 'processor\t: 0\nflags\t: ' + ' '.join(flags if flags is not None else cpu.REQUIRED[abi]) + '\n'
    else:
        text = 'Processor: synthetic ARM metadata fixture\nHardware: fixture\n'
    source = directory / 'guest-cpuinfo.txt'
    source.write_text(text, encoding='utf-8')
    report = directory / 'guest-cpu-baseline.json'
    report.write_text(json.dumps(cpu.inspect(source.read_bytes(), abi), sort_keys=True, indent=2) + '\n', encoding='utf-8')
    return {cpu.FIELDS[0]: cpu.digest(source), cpu.FIELDS[1]: cpu.digest(report)}
