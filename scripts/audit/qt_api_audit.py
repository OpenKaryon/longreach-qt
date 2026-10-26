#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
#
# Qt public-API audit: regenerates the class databases check_coverage.py
# measures against (qt-api-classes*.txt) from an unpacked Qt source tree.
#
# Classes are the declarations exported (Q_<MODULE>_EXPORT) from public, non
# _p.h headers; methods are counted heuristically. Qt 6 and Qt 4 write
# suffixed files; the version is read from the directory name, or --qt N.
#
# Usage: python scripts/audit/qt_api_audit.py <qt-everywhere-src dir>
#            [--skip a,b] [--qt 4|5|6] [--out DIR]

import io, os, re, sys, glob
from collections import defaultdict

ROOT = sys.argv[1]
# qtwebengine: Chromium, out of scope. qttools: four Designer plugin types in
# headers without the _p.h suffix that applications cannot include.
SKIP = {"qtwebengine", "qttools"}
for i, a in enumerate(sys.argv):
    if a == "--skip" and i + 1 < len(sys.argv):
        SKIP = set(sys.argv[i + 1].split(","))
SCRIPT_DIR = os.path.dirname(os.path.abspath(sys.argv[0]))
OUT = os.path.normpath(os.path.join(SCRIPT_DIR, "..", "tests"))

# The version, from the directory name (qt-everywhere-src-6.8.5 and so on).
QT_MAJOR = None
for i, a in enumerate(sys.argv):
    if a == "--qt" and i + 1 < len(sys.argv):
        QT_MAJOR = int(sys.argv[i + 1])
    if a == "--out" and i + 1 < len(sys.argv):
        OUT = os.path.abspath(sys.argv[i + 1])
if QT_MAJOR is None:
    m = re.search(r"qt-everywhere-\S*?-?(\d+)\.\d+", os.path.basename(os.path.normpath(ROOT)))
    if not m:
        sys.exit("cannot tell the Qt major version from %r - pass --qt 4, 5 or 6"
                 % os.path.basename(os.path.normpath(ROOT)))
    QT_MAJOR = int(m.group(1))

# Qt 5's files keep the names they have always had, so existing tooling and the
# committed database are untouched; Qt 6 gets its own set alongside.
SUFFIX = "" if QT_MAJOR == 5 else "-qt%d" % QT_MAJOR

def outfile(stem):
    return os.path.join(OUT, "%s%s.txt" % (stem, SUFFIX))

def read(p):
    try:
        return io.open(p, encoding="utf-8", errors="ignore").read()
    except Exception:
        return ""

# Qt 4 is one tree with its modules under src/; Qt 5 and 6 are qt* repositories.
def module_srcdir(module):
    if QT_MAJOR == 4:
        return os.path.join(ROOT, "src", module)
    return os.path.join(ROOT, module, "src")


# Qt 4 directories mapped to the repository names their contents became, so
# the side-by-side report lines up; qt3support keeps its own name.
QT4_MODULE_NAMES = {
    "corelib": "qtbase", "gui": "qtbase", "network": "qtbase", "sql": "qtbase",
    "xml": "qtbase", "testlib": "qtbase", "opengl": "qtbase", "dbus": "qtbase",
    "openvg": "qtbase", "activeqt": "qtbase", "plugins": "qtbase",
    "svg": "qtsvg",
    "script": "qtscript", "scripttools": "qtscript",
    "xmlpatterns": "qtxmlpatterns",
    "declarative": "qtdeclarative", "imports": "qtdeclarative",
    "multimedia": "qtmultimedia",
    "qt3support": "qt3support",
}


def module_label(module):
    return QT4_MODULE_NAMES.get(module, module) if QT_MAJOR == 4 else module


def public_headers(module):
    out, srcdir = [], module_srcdir(module)
    if not os.path.isdir(srcdir):
        return out
    for dp, dn, fn in os.walk(srcdir):
        low = dp.replace("\\", "/").lower()
        if "/3rdparty/" in low or "/private/" in low or "/tests/" in low:
            continue
        for f in fn:
            if f.endswith(".h") and not f.endswith("_p.h") and not f.endswith("_pch.h"):
                out.append(os.path.join(dp, f))
    return out

# QtDataVisualization uses QT_DATAVISUALIZATION_EXPORT (no underscore after Q),
# unlike every other module's Q_<MODULE>_EXPORT - accept both.
CLASS_RE = re.compile(r'\b(class|struct)\s+QT?_[A-Z0-9_]+_EXPORT\s+([A-Za-z_]\w*)')
METHOD_RE = re.compile(
    r'^[ \t]*(?!#)(?!Q_DECLARE)(?!Q_DISABLE)(?!Q_ENUM)(?!Q_PROPERTY)(?!friend)'
    r'(?:[A-Za-z_][\w:<>,\*&\s]*?\s[\*&]?)?'
    r'([A-Za-z_]\w*)\s*\([^;{}]*\)\s*(?:const)?\s*(?:noexcept)?\s*'
    r'(?:override|final|=\s*0|=\s*default|=\s*delete)?\s*;')
BADNAMES = {"if","for","while","switch","return","sizeof","emit","Q_OBJECT","explicit"}

def extract_classes(txt):
    """Return list of (class_name, [method_names]) via brace-matched bodies."""
    res = []
    for m in CLASS_RE.finditer(txt):
        name = m.group(2)
        # Only public Qt classes (QXxx, and QtDataVisualization's Q3Dxxx); exported
        # helpers would only skew the percentage.
        if not re.match(r'Q[A-Z0-9]', name):
            continue
        # find opening brace of this class (skip base-clause up to ; or {)
        i = m.end()
        semi = txt.find(";", i)
        brace = txt.find("{", i)
        if brace == -1 or (semi != -1 and semi < brace):
            continue  # forward declaration, no body
        depth, j, n = 0, brace, len(txt)
        while j < n:
            c = txt[j]
            if c == "{": depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    break
            j += 1
        body = txt[brace + 1:j]
        methods = []
        for line in body.splitlines():
            mm = METHOD_RE.match(line)
            if mm and mm.group(1) not in BADNAMES and mm.group(1) != name.lstrip("~"):
                methods.append(mm.group(1))
            elif mm and mm.group(1) in (name, "~" + name):
                methods.append(mm.group(1))  # keep ctor/dtor
        res.append((name, methods))
    return res

if QT_MAJOR == 4:
    # Everything under src/ except the vendored third-party code and the build
    # tools, neither of which is Qt API.
    _src = os.path.join(ROOT, "src")
    modules = sorted(d for d in os.listdir(_src)
                     if os.path.isdir(os.path.join(_src, d))
                     and d not in ("3rdparty", "tools"))
else:
    modules = sorted(d for d in os.listdir(ROOT)
                     if d.startswith("qt") and os.path.isdir(os.path.join(ROOT, d)))

inv = {}                 # module -> {class: [methods]}
class_owner = {}
for mod in modules:
    if mod in SKIP:
        continue
    cls = {}
    for h in public_headers(mod):
        for name, methods in extract_classes(read(h)):
            if name not in cls:
                cls[name] = methods
                class_owner.setdefault(name, module_label(mod))
            else:
                cls[name].extend(m for m in methods if m not in cls[name])
    if cls:
        inv[module_label(mod)] = dict(inv.get(module_label(mod), {}), **cls)

known = set(class_owner)

# examples
QCLASS = re.compile(r'\bQ[A-Z0-9][A-Za-z0-9]+\b')
mod_examples = defaultdict(list)
def leaf_examples(module):
    exdir = os.path.join(ROOT, module, "examples")
    if not os.path.isdir(exdir):
        return
    for pro in glob.glob(os.path.join(exdir, "**", "*.pro"), recursive=True):
        txt = read(pro)
        if re.search(r'TEMPLATE\s*=\s*subdirs', txt):
            continue
        d = os.path.dirname(pro)
        srcs = " ".join(read(f) for f in
                        glob.glob(os.path.join(d, "*.cpp")) + glob.glob(os.path.join(d, "*.h")))
        used = set(QCLASS.findall(srcs)) & known
        mod_examples[module].append(used)

for mod in modules:
    if mod not in SKIP:
        leaf_examples(mod)

used_classes, ex_count, mod_used = set(), 0, defaultdict(set)
for mod, exs in mod_examples.items():
    for used in exs:
        ex_count += 1
        used_classes |= used
        mod_used[mod] |= used

tot_classes = sum(len(c) for c in inv.values())
tot_methods = sum(len(ms) for c in inv.values() for ms in c.values())

# ---- terminal report ----
print("=" * 78)
print("QT %d PUBLIC API  (skipped: %s)" % (QT_MAJOR, ", ".join(sorted(SKIP))))
print("=" * 78)
print("%-20s %8s %9s %9s %9s" % ("module","classes","~methods","examples","cls-used"))
for mod in sorted(inv, key=lambda m: -len(inv[m])):
    nm = sum(len(v) for v in inv[mod].values())
    print("%-20s %8d %9d %9d %9d" %
          (mod, len(inv[mod]), nm, len(mod_examples.get(mod, [])), len(mod_used.get(mod, set()))))
print("-" * 78)
print("%-20s %8d %9d %9d %9d" % ("TOTAL", tot_classes, tot_methods, ex_count, len(used_classes)))
print()
print("Example class coverage: %d / %d = %.1f%%" %
      (len(used_classes), tot_classes, 100.0*len(used_classes)/max(tot_classes,1)))
print("(methods = heuristic count of declarations in class bodies)")

# ---- files ----
with io.open(outfile("qt-api-inventory"),"w",encoding="utf-8",newline="\n") as f:
    for mod in sorted(inv):
        nm = sum(len(v) for v in inv[mod].values())
        f.write("\n#### %s : %d classes, %d methods\n" % (mod, len(inv[mod]), nm))
        for cname in sorted(inv[mod]):
            ms = inv[mod][cname]
            f.write("  %s  (%d)\n" % (cname, len(ms)))
            for mth in ms:
                f.write("      %s()\n" % mth)
with io.open(outfile("qt-api-classes"),"w",encoding="utf-8",newline="\n") as f:
    for c in sorted(known):
        f.write("%s\t%s\n" % (c, class_owner[c]))
with io.open(outfile("classes-used-by-examples"),"w",encoding="utf-8",newline="\n") as f:
    for c in sorted(used_classes):
        f.write("%s\t%s\n" % (c, class_owner.get(c,"?")))
with io.open(outfile("classes-not-covered"),"w",encoding="utf-8",newline="\n") as f:
    for c in sorted(known - used_classes):
        f.write("%s\t%s\n" % (c, class_owner.get(c,"?")))
print("wrote into %s: %s" % (OUT, ", ".join(os.path.basename(outfile(x)) for x in
      ["qt-api-inventory", "qt-api-classes", "classes-used-by-examples", "classes-not-covered"])))
