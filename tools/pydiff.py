#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Differential probe: run a .py under CPython AND under pxx, diff, and on a
mismatch bisect down to the statement that first diverges.

    tools/pydiff.py run    prog.py            # diff stdout/stderr/exit code
    tools/pydiff.py bisect prog.py            # name the first diverging statement
    tools/pydiff.py probe                     # the built-in NilPy probe corpus

Why this exists
---------------
The expensive NilPy bugs do not crash. They produce a *plausible wrong value*.
`bug-nilpy-not-on-object-always-true` returned confident, well-formatted key
analysis with the WRONG keys and no error at all: `if not match:` over an
`re.match` result was always true, so every chord came back unclassified. No
poison, no trace, no debugger breakpoint would have found it — it was found by
diffing one helper's output against CPython, by hand.

CPython is the oracle NilPy is defined against, so that diff should be a command
rather than something each session improvises. Track T's `fpc_diff_probe.sh` is
the same idea for Pascal against FPC, and it found three bugs.

The bisect
----------
Bisecting a program by truncation does not work — cutting a program changes its
output wholesale. What DOES work: keep every import, function and class
definition (they have no output of their own), and vary how many top-level
EXECUTABLE statements run. The first prefix length whose output diverges names
the statement that first shows the bug. That is the manual narrowing this
session did by hand, automated.

Exit status: 0 = agreement, 1 = divergence, 2 = harness problem.
"""

import argparse
import ast
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_PXX = os.path.join(ROOT, "compiler", "pascal26")
TIMEOUT = 60


class Result:
    def __init__(self, out, err, code, note=""):
        self.out, self.err, self.code, self.note = out, err, code, note

    def key(self):
        # stderr is NOT compared: pxx and CPython word diagnostics differently
        # and always will. stdout plus exit status is the contract.
        return (self.out, self.code)


def run_cpython(path, argv):
    try:
        p = subprocess.run([sys.executable, path] + argv, capture_output=True,
                           text=True, timeout=TIMEOUT, cwd=os.path.dirname(path) or ".")
        return Result(p.stdout, p.stderr, p.returncode)
    except subprocess.TimeoutExpired:
        return Result("", "", -1, "timeout")


def run_pxx(path, argv, pxx):
    d = os.path.dirname(path) or "."
    exe = os.path.join(tempfile.mkdtemp(prefix="pydiff-"), "a.out")
    try:
        c = subprocess.run([pxx, os.path.basename(path), exe], capture_output=True,
                           text=True, timeout=TIMEOUT, cwd=d)
    except subprocess.TimeoutExpired:
        return Result("", "", -1, "compile timeout")
    if c.returncode != 0 or not os.path.exists(exe):
        # A compile failure on code CPython accepts IS a divergence — usually a
        # missing builtin or an unsupported form — so report it, do not skip it.
        return Result("", c.stdout + c.stderr, -2, "compile failed")
    try:
        p = subprocess.run([exe] + argv, capture_output=True, text=True,
                           timeout=TIMEOUT, cwd=d)
        return Result(p.stdout, p.stderr, p.returncode)
    except subprocess.TimeoutExpired:
        return Result("", "", -1, "timeout")


def report(path, a, b, verbose=True):
    if a.key() == b.key():
        return True
    if verbose:
        print("DIFF %s" % path)
        if a.note or b.note:
            print("  note: cpython=%s pxx=%s" % (a.note or "ok", b.note or "ok"))
        if a.code != b.code:
            print("  exit: cpython=%s pxx=%s" % (a.code, b.code))
        if a.out != b.out:
            al, bl = a.out.splitlines(), b.out.splitlines()
            for i in range(max(len(al), len(bl))):
                x = al[i] if i < len(al) else "<no line>"
                y = bl[i] if i < len(bl) else "<no line>"
                if x != y:
                    print("  line %d:" % (i + 1))
                    print("    cpython: %s" % x)
                    print("    pxx    : %s" % y)
        if b.note == "compile failed":
            tail = [l for l in b.err.strip().splitlines() if l.strip()][-3:]
            for l in tail:
                print("  %s" % l)
    return False


def split_module(src):
    """(preamble, [executable top-level statements]) as source text.

    Imports, defs and classes go in the preamble: they define, they do not
    print, so every prefix keeps them."""
    tree = ast.parse(src)
    keep, execs = [], []
    for node in tree.body:
        if isinstance(node, (ast.Import, ast.ImportFrom, ast.FunctionDef,
                             ast.AsyncFunctionDef, ast.ClassDef)):
            keep.append(node)
        else:
            execs.append(node)
    return keep, execs


def bisect(path, argv, pxx):
    src = open(path).read()
    try:
        keep, execs = split_module(src)
    except SyntaxError as e:
        print("cannot parse %s: %s" % (path, e))
        return 2
    if not execs:
        print("no top-level executable statements to bisect")
        return 2

    print("bisecting %d top-level statements" % len(execs))
    prev_ok = 0
    for k in range(1, len(execs) + 1):
        mod = ast.Module(body=keep + execs[:k], type_ignores=[])
        text = ast.unparse(ast.fix_missing_locations(mod))
        tmp = os.path.join(os.path.dirname(path) or ".", "__pydiff_bisect.py")
        with open(tmp, "w") as f:
            f.write(text + "\n")
        try:
            a = run_cpython(tmp, argv)
            b = run_pxx(tmp, argv, pxx)
        finally:
            os.unlink(tmp)
        if a.key() == b.key():
            prev_ok = k
            continue
        line = getattr(execs[k - 1], "lineno", "?")
        print("\nfirst divergence at top-level statement %d (source line %s):" % (k, line))
        print("  %s" % ast.unparse(execs[k - 1]).splitlines()[0][:100])
        print("  (statements 1..%d agree)" % prev_ok)
        report(path, a, b)
        return 1
    print("no divergence in any prefix — the whole program agrees")
    return 0


# Built-in corpus. Each entry is a self-contained program exercising one
# primitive against CPython. Kept small on purpose: a probe that fails should
# name the bug, not require reading.
PROBES = [
    ("not-on-object", '''
import re
m = re.match(r'^(A)$', "A")
print("not m ->", not m)
print("m is None ->", m is None)
'''),
    ("not-on-class-instance", '''
class K:
    def __init__(self, v: int):
        self.v = v
o = K(1)
print("not o ->", not o)
'''),
    ("not-on-container", '''
xs = [1, 2]
ys = []
print(not xs, not ys)
'''),
    ("truthiness-str", '''
print(not "", not "x", bool(""), bool("x"))
'''),
    ("def-value-in-a-name", '''
def f(ch: str) -> str:
    return "hi " + ch
def g(cb) -> str:
    return cb("x")
print(g(f))
x = f
print(g(x))
'''),
    ("slice-of-dict-get", '''
d = {"C": ["a", "b", "c", "d"]}
b = d.get("C", [])
print(len(b[:2]), b[:2])
'''),
    ("environ", '''
import os
print(os.environ.get("PYDIFF_PROBE", "<unset>"))
'''),
    ("int-div-mod", '''
for a, b in [(7, 2), (-7, 2), (7, -2), (-7, -2)]:
    print(a, b, a // b, a % b)
'''),
]


def probe(pxx):
    d = tempfile.mkdtemp(prefix="pydiff-probe-")
    bad = 0
    for name, src in PROBES:
        p = os.path.join(d, name.replace("-", "_") + ".py")
        with open(p, "w") as f:
            f.write(src.strip() + "\n")
        a = run_cpython(p, [])
        b = run_pxx(p, [], pxx)
        if a.key() == b.key():
            print("ok   %s" % name)
        else:
            bad += 1
            report(name, a, b)
    print("\n%d/%d probes agree with CPython" % (len(PROBES) - bad, len(PROBES)))
    return 1 if bad else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mode", choices=["run", "bisect", "probe"])
    ap.add_argument("file", nargs="?")
    ap.add_argument("args", nargs="*", help="arguments passed to the program")
    ap.add_argument("--pxx", default=os.environ.get("PXX", DEFAULT_PXX))
    a = ap.parse_args()

    if not os.path.exists(a.pxx):
        print("compiler not found: %s (set --pxx or $PXX)" % a.pxx)
        return 2
    if a.mode == "probe":
        return probe(a.pxx)
    if not a.file:
        print("%s needs a file" % a.mode)
        return 2
    if a.mode == "bisect":
        return bisect(a.file, a.args, a.pxx)
    ca = run_cpython(a.file, a.args)
    pa = run_pxx(a.file, a.args, a.pxx)
    if report(a.file, ca, pa):
        print("ok %s (%d lines of stdout agree)" % (a.file, len(ca.out.splitlines())))
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
