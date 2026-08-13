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
    """Both arms run from the file's own directory, so relative imports and
    sibling data files resolve the same way for CPython and for pxx.

    The script path must therefore be BASENAME (or absolute), never the caller's
    relative path: `pydiff.py run test/x.npy` from the repo root ran
    `python3 test/x.npy` from inside `test/`, so CPython exited 2 with no
    stdout and every line reported `cpython: <no line>` — a whole-file DIFF that
    looks exactly like a real divergence, on the oracle the debugging playbook
    tells you to trust over reasoning (bug-t-pydiff-cpython-arm-fails-on-a-
    relative-path). run_pxx below already got this right, which is why only one
    arm went silent.
    """
    d = os.path.dirname(path) or "."
    try:
        p = subprocess.run([sys.executable, os.path.basename(path)] + argv,
                           capture_output=True, text=True, timeout=TIMEOUT, cwd=d)
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
    # ---- REAL PROGRAMS ----------------------------------------------------
    # Added 2026-08-06 after a day of bughunting in which ~40 unit-shaped
    # probes over arithmetic, strings, lists, dicts, classes, slicing,
    # closures and exceptions came back almost entirely GREEN — and then a
    # plain matrix multiply broke immediately.
    #
    # Features in isolation work; COMBINATIONS break. Every entry below is a
    # small program a person would actually write, and three of them are here
    # because they each caught a silent bug no unit probe had:
    #
    #   prog-matrix            -> a nested comprehension over range() ran ONCE
    #                             and every row was the same list object
    #   prog-tokenizer-parser  -> a nested def's own local counted as a capture,
    #                             AND a method call in a `while` condition was
    #                             evaluated once, so the scanner never stopped
    #   prog-aggregate         -> `d[k]["n"] += 1` computed and never stored
    #
    # When adding here, prefer a program over a feature. Keep it deterministic
    # (no time, no randomness, and SORT anything set-derived — set order is
    # unspecified and CPython's own varies per run).
    #
    # Use a RAW triple-quoted string (r'''...''') for the source. A plain one
    # eats the program's own backslash escapes: prog-json's `"{\n"` arrived as a
    # literal newline and CPython refused the file with an unterminated string
    # literal, which reads like a pxx bug and is not one.
    ("prog-matrix", r'''
def mk(r, c, f):
    return [[f(i,j) for j in range(c)] for i in range(r)]
A = mk(3,3, lambda i,j: i*3+j)
B = mk(3,3, lambda i,j: 1 if i==j else 0)
def mul(X, Y):
    n = len(X); m = len(Y[0]); k = len(Y)
    out = []
    for i in range(n):
        row = []
        for j in range(m):
            s = 0
            for t in range(k):
                s += X[i][t]*Y[t][j]
            row.append(s)
        out.append(row)
    return out
print(A)
print(mul(A,B))
print(mul(A,A))
def transpose(X):
    return [[X[i][j] for i in range(len(X))] for j in range(len(X[0]))]
print(transpose(A))
tot = 0
for row in A:
    for v in row:
        tot += v
print("sum", tot)
'''),
    ("prog-tokenizer-parser", r'''
def tokenize(s):
    toks = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == " ":
            i += 1
            continue
        if c in "+-*/()":
            toks.append(c); i += 1; continue
        if c.isdigit():
            j = i
            while j < len(s) and s[j].isdigit(): j += 1
            toks.append(s[i:j]); i = j; continue
        raise ValueError("bad char " + c)
    return toks
print(tokenize("12 + 34*(5-6)"))
def evaluate(toks):
    pos = [0]
    def peek():
        return toks[pos[0]] if pos[0] < len(toks) else None
    def take():
        t = toks[pos[0]]; pos[0] += 1; return t
    def factor():
        t = take()
        if t == "(":
            v = expr(); take(); return v
        return int(t)
    def term():
        v = factor()
        while peek() in ("*","/"):
            op = take()
            r = factor()
            v = v * r if op == "*" else v // r
        return v
    def expr():
        v = term()
        while peek() in ("+","-"):
            op = take()
            r = term()
            v = v + r if op == "+" else v - r
        return v
    return expr()
print(evaluate(tokenize("12 + 34*(5-6)")))
print(evaluate(tokenize("2*3+4*5")))
print(evaluate(tokenize("(1+2)*(3+4)")))
'''),
    ("prog-aggregate", r'''
def process(recs):
    out = {}
    for r in recs:
        cat = r["cat"]
        if cat not in out:
            out[cat] = {"n": 0, "sum": 0, "items": []}
        out[cat]["n"] += 1
        out[cat]["sum"] += r["val"]
        out[cat]["items"].append(r["id"])
    return out
recs = []
for i in range(60):
    recs.append({"id": i, "cat": "abc"[i % 3], "val": (i * 13) % 17})
res = process(recs)
for c in sorted(res.keys()):
    e = res[c]
    print(c, e["n"], e["sum"], e["items"][:4], e["items"][-2:])
tot = 0
for c in res:
    tot += res[c]["sum"]
print("tot", tot)
'''),
    ("prog-graph", r'''
edges = {"a":["b","c"], "b":["d"], "c":["d","e"], "d":["e"], "e":[]}
def bfs(start):
    seen = [start]
    queue = [start]
    order = []
    while len(queue) > 0:
        n = queue[0]
        queue = queue[1:]
        order.append(n)
        for m in edges[n]:
            if m not in seen:
                seen.append(m)
                queue.append(m)
    return order
print(bfs("a"))
def dfs(n, seen):
    if n in seen: return []
    seen.append(n)
    out = [n]
    for m in edges[n]:
        out.extend(dfs(m, seen))
    return out
print(dfs("a", []))
def toposort():
    indeg = {}
    for k in edges: indeg[k] = 0
    for k in edges:
        for m in edges[k]:
            indeg[m] = indeg[m] + 1
    ready = sorted([k for k in indeg if indeg[k] == 0])
    out = []
    while len(ready) > 0:
        n = ready[0]; ready = ready[1:]
        out.append(n)
        for m in edges[n]:
            indeg[m] -= 1
            if indeg[m] == 0:
                ready.append(m)
                ready = sorted(ready)
    return out
print(toposort())
'''),
    ("prog-lru", r'''
class LRU:
    def __init__(self, cap):
        self.cap = cap
        self.keys = []
        self.vals = {}
    def get(self, k):
        if k not in self.vals: return -1
        self.keys.remove(k)
        self.keys.append(k)
        return self.vals[k]
    def put(self, k, v):
        if k in self.vals:
            self.keys.remove(k)
        elif len(self.keys) >= self.cap:
            old = self.keys[0]
            self.keys = self.keys[1:]
            del self.vals[old]
        self.keys.append(k)
        self.vals[k] = v
c = LRU(2)
c.put("a",1); c.put("b",2)
print(c.get("a"))
c.put("c",3)
print(c.get("b"), c.get("a"), c.get("c"))
print(sorted(c.vals.items()), c.keys)
'''),
    ("prog-json", r'''
def dumps(v, ind=0):
    sp = " " * ind
    if isinstance(v, dict):
        if len(v) == 0: return "{}"
        parts = []
        for k in sorted(v.keys()):
            parts.append(sp + "  " + '"' + str(k) + '": ' + dumps(v[k], ind+2))
        return "{\n" + ",\n".join(parts) + "\n" + sp + "}"
    if isinstance(v, list):
        if len(v) == 0: return "[]"
        parts = []
        for e in v:
            parts.append(sp + "  " + dumps(e, ind+2))
        return "[\n" + ",\n".join(parts) + "\n" + sp + "]"
    if isinstance(v, str): return '"' + v + '"'
    if isinstance(v, bool): return "true" if v else "false"
    if v is None: return "null"
    return str(v)
doc = {"name":"x","tags":["a","b"],"meta":{"n":3,"ok":True,"none":None},"empty":[],"eo":{}}
print(dumps(doc))
'''),

    # ---- UNIT SHAPES ------------------------------------------------------
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
