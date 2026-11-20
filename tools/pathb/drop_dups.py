#!/usr/bin/env python3
"""Archive semantics for a flat --link: BASE objects are always linked; a LIB
object is pulled only when it defines a symbol the linked set still leaves
undefined, iterated to a fixpoint, as ld does for a .a. A pulled LIB object
that also defines a symbol BASE already defines strongly gets a copy with that
symbol made local -- what gcc's `weak' gives (libXfont's stubs and
serverGeneration: pxx claims __GNUC__ 2.7, so libXfont's `weak' macro is
empty). usage: drop_dups.py OUTDIR 'BASE...' 'LIB...' [first]
`first': after each pull the scan restarts at the head of LIB, so a symbol
comes from the EARLIEST library object that defines it -- ld's order when one
library replaces another's member (libXaw's Vendor.o over libXt's). Without
it, one sweep can pass the earlier provider before the need arises."""
import os, subprocess, sys
def syms(o):
    d, u = set(), set()
    for l in subprocess.run(["nm", "-g", o], capture_output=True, text=True).stdout.splitlines():
        p = l.split()
        if len(p) == 2 and p[0] in "Uw": u.add(p[1])
        elif len(p) >= 3 and p[1] in "TDBRC": d.add(p[-1])
    return d, u
outdir = sys.argv[1]; base = sys.argv[2].split(); lib = sys.argv[3].split()
first = len(sys.argv) > 4 and sys.argv[4] == "first"
os.makedirs(outdir, exist_ok=True)
info = {o: syms(o) for o in base + lib}
basedef = set()
for o in base: basedef |= info[o][0]
defined, undef = set(basedef), set()
for o in base: undef |= info[o][1]
kept, changed = [], True
while changed:
    changed = False
    for o in lib:
        if o in kept: continue
        if info[o][0] & (undef - defined):
            kept.append(o); defined |= info[o][0]; undef |= info[o][1]; changed = True
            if first: break
res = []
for o in lib:
    if o not in kept:
        sys.stderr.write(f"not pulled: {os.path.basename(o)}\n"); continue
    dup = sorted(info[o][0] & basedef)
    if dup:
        n = os.path.join(outdir, os.path.basename(o))
        subprocess.run(["objcopy"] + [f"--localize-symbol={s}" for s in dup] + [o, n], check=True)
        sys.stderr.write(f"localized in {os.path.basename(o)}: {dup}\n"); o = n
    res.append(o)
print(" ".join(res))
