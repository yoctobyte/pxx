#!/usr/bin/env python3
"""Replay objects for every member of some of a package's own archives.
usage: arc_objs.py PKG DIR ARCHIVE...
DIR is relative to $PATHB_WORK/src/PKG; each ARCHIVE is relative to DIR, as
on gcc's link line (Xorg's ../../dix/.libs/libdix.a). A member foo.o of
X/.libs/libY.a is the replay object of X/foo.c, $PATHB_WORK/replay/PKG/
X_foo.c.o (libtool may prefix it: libdix_la-foo.o); one compiled from another
directory (kdrive/src's ../../mi/miinitext.c) is the one replay object with
that stem. Prints the objects, space-separated, each once; a member with no
object goes to stderr and exits 1. (xfb_objs.py does this for Xfbdev.)"""
import os, subprocess, sys
B = os.path.realpath(os.environ["PATHB_WORK"])  # make logs hold resolved paths
pkg, d0, arcs = sys.argv[1], sys.argv[2], sys.argv[3:]
S, R = f"{B}/src/{pkg}", f"{B}/replay/{pkg}"
objs = set(os.listdir(R))
out, bad = [], 0
for a in arcs:
    ap = os.path.normpath(os.path.join(S, d0, a))
    d = os.path.relpath(os.path.dirname(ap), S).replace("/.libs", "").replace(".libs", "")
    d = "" if d in (".", "") else d
    pre = d.replace("/", "_") + "_" if d else ""
    for m in subprocess.run(["ar", "t", ap], capture_output=True, text=True, check=True).stdout.split():
        stem = m[:-2]
        hit = None
        for cand in (stem, stem.split("-", 1)[-1]):   # libdix_la-foo.o -> foo
            if f"{pre}{cand}.c.o" in objs:
                hit = f"{pre}{cand}.c.o"; break
        if not hit:
            for cand in (stem, stem.split("-", 1)[-1]):
                hits = sorted(f for f in objs if f.endswith(f"_{cand}.c.o") or f == f"{cand}.c.o")
                if len(hits) == 1:
                    hit = hits[0]; break
        if not hit:
            sys.stderr.write(f"arc_objs: {pkg} {a}: no replay object for {m}\n"); bad += 1
            continue
        p = f"{R}/{hit}"
        if p not in out: out.append(p)
print(" ".join(out))
sys.exit(1 if bad else 0)
