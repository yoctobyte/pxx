#!/usr/bin/env python3
"""Which ir.inc routines are reached ONLY from C-guarded call sites?

The method that found slice 1: FOLLOW CALLERS, NOT THE GUARD. A routine can be
entirely C-exclusive and contain no `CProgramMode` at all, so the grep that
defined this refactor cannot see it. This walks the other way.

Conservative by construction: a routine is reported only when EVERY call site
across the whole compiler is inside ir.inc/cir.inc and under a C guard, or
inside another routine already established as C-only. Anything unclear is left
out -- a missed candidate costs nothing, a wrong one costs a wrong move.
"""
import re, os, sys, collections

ROOT = os.path.expanduser("~/frankC/compiler")
FILES = [f for f in sorted(os.listdir(ROOT)) if f.endswith((".inc", ".pas"))]

DEF = re.compile(r'^(?:function|procedure)\s+([A-Za-z_]\w*)', re.M)

def load(f):
    return open(os.path.join(ROOT, f), encoding="utf-8", errors="replace").read()

src = {f: load(f) for f in FILES}

# routines DEFINED in ir.inc (bodies, not forwards)
irlines = src["ir.inc"].split("\n")
defs = []   # (name, start_line_idx)
for i, ln in enumerate(irlines):
    m = re.match(r'^(?:function|procedure)\s+([A-Za-z_]\w*)', ln)
    if m and not ln.rstrip().endswith("forward;"):
        defs.append((m.group(1), i))

# body span of each: from its line to the next def line
spans = {}
for k, (name, i) in enumerate(defs):
    end = defs[k+1][1] if k+1 < len(defs) else len(irlines)
    spans.setdefault(name, []).append((i, end))

known_c = set()
if os.path.exists(os.path.join(ROOT, "cir.inc")):
    known_c = set(DEF.findall(src["cir.inc"]))

def call_sites(name):
    """every (file, lineno) that MENTIONS name outside its own definition"""
    out = []
    pat = re.compile(r'\b' + re.escape(name) + r'\b')
    for f, text in src.items():
        for i, ln in enumerate(text.split("\n")):
            if not pat.search(ln):
                continue
            if re.match(r'^(?:function|procedure)\s+' + re.escape(name) + r'\b', ln):
                continue
            if f == "ir.inc" and any(a <= i < b for a, b in spans.get(name, [])):
                continue          # recursive self-call
            out.append((f, i, ln.strip()))
    return out

def enclosing(f, i):
    """name of the routine containing line i of file f"""
    lines = src[f].split("\n")
    for j in range(i, -1, -1):
        m = re.match(r'^(?:function|procedure)\s+([A-Za-z_]\w*)', lines[j])
        if m and not lines[j].rstrip().endswith("forward;"):
            return m.group(1)
    return "<top>"

print("== ir.inc routines whose every mention is inside ir.inc/cir.inc ==")
print("   (candidates only -- the C-guard check is by eye, below)\n")
cands = []
for name in sorted(spans):
    sites = call_sites(name)
    if not sites:
        continue
    files = {f for f, _, _ in sites}
    if not files <= {"ir.inc", "cir.inc"}:
        continue
    callers = sorted({enclosing(f, i) for f, i, _ in sites if not _.rstrip().endswith("forward;")})
    cands.append((name, len(sites), callers, sites))

for name, n, callers, sites in cands:
    tag = "  <-- callers all already C-only" if callers and set(callers) <= known_c else ""
    print(f"{name:34s} {n:3d} mention(s)  callers: {', '.join(callers)}{tag}")
