# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon

import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text()
instruction = re.compile(r"^\s*([a-z][a-z0-9.+-]*)\s+(.*?)\s*$")
registers = {
    "lwarx": (0, 2),
    "stwcx.": (0, 2),
    "addi": (0, 1),
    "add": (0, 1, 2),
    "xor.": (0, 1, 2),
    "mr": (0, 1),
    "mftb": (0,),
    "mftbu": (0,),
    "rlwinm": (0, 1),
    "or": (0, 1, 2),
}

def atomic_block(match):
    lines = match[0].splitlines()
    if any(re.search(r"\blwarx\b", line) for line in lines):
        for index, line in enumerate(lines):
            local = re.match(r"^(\s*)(\d+):\s*(.*)$", line)
            if local:
                indent, number, rest = local.groups()
                label = f"Lqt_atomiclocal{match.start()}_{number}"
                lines[index] = indent + rest
                lines.insert(index, label + ":")
                lines = [re.sub(rf"(\bb\w*-?\s+){number}b\b", rf"\g<1>{label}", entry) for entry in lines]
                break
    instructions = [(i, m) for i, line in enumerate(lines) if (m := instruction.match(line.split(";", 1)[0] + " " if line.strip() in ("isync", "eieio", "sync") else line))]
    if not any(m[1] in ("lwarx", "mftb", "mftbu", "rlwinm", "stw", "lwz") for _, m in instructions):
        return match[0]
    before = {}
    prefix = f"Lqt_atomic{match.start()}"
    for ordinal, (index, item) in enumerate(instructions):
        mnemonic, raw = item.groups()
        args = [arg.strip() for arg in raw.split(",")]
        if mnemonic in registers:
            for arg in registers[mnemonic]:
                if args[arg].isdigit():
                    args[arg] = "r" + args[arg]
        elif mnemonic in ("stw", "lwz") and len(args) == 2:
            if args[0].isdigit():
                args[0] = "r" + args[0]
            args[1] = re.sub(r"\((\d+)\)$", r"(r\1)", args[1])
        elif mnemonic.startswith("b") and re.fullmatch(r"\$[+-]\d+", raw):
            offset = int(raw[1:])
            assert offset % 4 == 0
            target = ordinal + offset // 4
            assert 0 <= target <= len(instructions), (raw, lines)
            dest = instructions[target][0] if target < len(instructions) else len(lines) - 1
            label = before.setdefault(dest, f"{prefix}_{target}:")
            args = [label[:-1]]
        lines[index] = "\t" + mnemonic + "\t" + ", ".join(args)
    for index in sorted(before, reverse=True):
        lines.insert(index, before[index])
    return "\n".join(lines)

text = re.sub(r"(?ms)^\s*; InlineAsm Start\n.*?^\s*; InlineAsm End", atomic_block, text)
path.write_bytes(text.encode())