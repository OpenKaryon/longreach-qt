# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon

import re
import sys
from pathlib import Path

source, dest = map(Path, sys.argv[1:])
text = source.read_text()
# Jaguar's ObjC 1 runtime requires a symtab even for a module with no
# class or category definitions. Clang uses null for this case.
module = re.compile(
    r"(?m)(^l_OBJC_MODULES:\n(?:[ \t]*\.long[^\n]*\n){3})([ \t]*\.long\s+)0\b[^\n]*"
)
text, empty_modules = module.subn(r"\g<1>\g<2>Lqt_empty_objc_symtab", text)
output = []
frames = []
labels = set(re.findall(r"^(\S+):", text, re.M))
labels.update(re.findall(r"^\s*\.(?:zero|tbss)fill\s+[^,]+,[^,]+,\s*([^,\s]+),", text, re.M))
weak = set(re.findall(r"^\s*\.(?:weak_definition|weak_def_can_be_hidden)\s+(\S+)", text, re.M))
needed = set(re.findall(r"(L[\w$]+\$non_lazy_ptr)", text))
frame = None
function = None
dso_handle = False

def register(name):
    if name == "lr":
        return 65
    if re.fullmatch(r"r[0-9]+", name):
        return int(name[1:])
    if re.fullmatch(r"f[0-9]+", name):
        return int(name[1:]) + 32
    if re.fullmatch(r"cr[0-7]", name):
        return int(name[2:]) + 68
    raise ValueError(name)

for line in text.splitlines():
    code = line.split(";", 1)[0].strip()
    if re.fullmatch(r'(?:_[\w$.]+|"[+-]\[[^"]+\]"):', code):
        function = code[:-1]
    if code.startswith(".section") and "__TEXT,__literal16,16byte_literals" in code:
        line = line.replace("__TEXT,__literal16,16byte_literals", "__TEXT,__const16,regular")
    if code.startswith(".macosx_version_min"):
        continue
    # The classic assembler cannot subtract a local PIC base from an
    # undefined symbol. Use an indirect pointer for function addresses too.
    match = re.search(r"(?:ha16|lo16)\((_[\w$.]+)-L[\w$]+\)", code)
    if match and (match[1] not in labels or match[1] in weak):
        target = match[1]
        if target == "___dso_handle":
            dso_handle = True
        else:
            slot = "L" + target + "$non_lazy_ptr"
            needed.add(slot)
            line = line.replace("(" + target + "-", "(" + slot + "-")
            if code.startswith("la "):
                line = re.sub(r"^(\s*)la\b", r"\1lwz", line)
            elif "lo16(" in code:
                raise ValueError(code)
    if not code.startswith(".cfi_"):
        output.append(line)
        continue
    op, *args = code.split(maxsplit=1)
    args = args[0].split(", ") if args else []
    if op == ".cfi_startproc":
        if function is None:
            raise ValueError("CFI without a function label")
        index = len(frames)
        prefix = f"Lqtcfi{index}"
        frame = {"prefix": prefix, "function": function, "rules": [], "personality": None, "lsda": None}
        frames.append(frame)
        output.append(prefix + "begin:")
    elif op == ".cfi_endproc":
        output.append(prefix + "end:")
        frame = None
    elif op == ".cfi_personality":
        assert args[0] == "155", args
        frame["personality"] = args[1]
    elif op == ".cfi_lsda":
        assert args[0] == "16", args
        frame["lsda"] = args[1]
    else:
        marker = prefix + "at" + str(len(frame["rules"]))
        output.append(marker + ":")
        if op == ".cfi_def_cfa_offset":
            rule = [".byte 14", f".uleb128 {int(args[0])}"]
        elif op == ".cfi_def_cfa_register":
            rule = [".byte 13", f".uleb128 {register(args[0])}"]
        elif op == ".cfi_offset":
            reg, offset = register(args[0]), int(args[1])
            assert offset % 4 == 0
            rule = [".byte 17", f".uleb128 {reg}", f".sleb128 {-offset // 4}"]
        else:
            raise ValueError(code)
        frame["rules"].append((marker, rule))

for symbol in sorted(needed - labels):
    target = symbol[1:].removesuffix("$non_lazy_ptr")
    output.extend([".non_lazy_symbol_pointer", symbol + ":",
                   ".indirect_symbol " + target, ".long 0"])

if empty_modules:
    output.extend([
        ".section __OBJC,__symbols,regular,no_dead_strip",
        ".align 2",
        "Lqt_empty_objc_symtab:",
        ".long 0,0",
        ".short 0,0",
    ])

if dso_handle:
    output.extend([".text", ".align 2", "___dso_handle:", ".long 0"])

output.append(".section __TEXT,__eh_frame,coalesced,no_toc+strip_static_syms+live_support")
for frame in frames:
    p = frame["prefix"]
    personality, lsda = frame["personality"], frame["lsda"]
    assert bool(personality) == bool(lsda)
    output += [".align 2", p.removeprefix("L")+"cie:", f".long {p}cieend-{p}ciedata",
               p+"ciedata:", ".long 0", ".byte 1"]
    if personality:
        output += [r'.ascii "zPLR\0"', ".byte 1,124,65,7,155",
                   f".long {personality}-.", ".byte 16,0"]
    else:
        output += [r'.ascii "zR\0"', ".byte 1,124,65,1,0"]
    output += [".byte 12,1,0", ".align 2", p+"cieend:",
               p+"fde:",
               f".long {p}fdeend-{p}fdedata", p+"fdedata:",
               f".long {p}fdedata-{p.removeprefix('L')}cie", f".long {frame['function']}",
               f".long {p}end-{p}begin"]
    output += [".byte 4", f".long {lsda}-."] if lsda else [".byte 0"]
    previous = p+"begin"
    for marker, rule in frame["rules"]:
        output += [".byte 4", f".long {marker}-{previous}", *rule]
        previous = marker
    output += [".align 2", p+"fdeend:"]
resolved = []
for line in output:
    match = re.fullmatch(r"\.long (Lqtcfi\d+(?:end|at\d+))-(Lqtcfi\d+(?:begin|at\d+))", line)
    if match:
        value = "Lqtdelta" + str(len(resolved))
        resolved.extend([f".set {value},{match[1]}-{match[2]}", f".long {value}"])
    else:
        resolved.append(line)
output = resolved
dest.write_bytes(("\n".join(output) + "\n").encode())
