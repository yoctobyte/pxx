#!/usr/bin/env python3
"""Print the pxx replay objects that make up gcc's static archives.
usage: libobjs.py PKG:ARCHIVE...   e.g. libxcb:libxcb libX11:libX11
An archive member foo.o is the replay object whose source basename is foo.c;
every replay object matched by some member is printed once."""
import os, subprocess, sys
B = os.path.realpath(os.environ["PATHB_WORK"])  # make logs hold resolved paths
out = []
for arg in sys.argv[1:]:
    pkg, lib = arg.split(":")
    members = subprocess.run(["ar", "t", f"{B}/stage/usr/lib/{lib}.a"], capture_output=True,
                             text=True, check=True).stdout.split()
    objs = [f for f in os.listdir(f"{B}/replay/{pkg}") if f.endswith(".c.o")]
    by_base = {}
    for o in objs:
        base = o[:-4].split("_")  # path parts joined by _, ambiguous; match on suffix instead
        by_base.setdefault(o, o)
    for m in sorted(set(members)):
        stem = m[:-2]
        # libtool prefixes a member when the library has per-target flags
        # (libXaw7.a holds libXaw7_la-Actions.o, from Actions.c)
        if stem.startswith(lib + "_la-"):
            stem = stem[len(lib) + 4:]
        # meson keeps the source suffix in the member (libdrm: xf86drm.c.o),
        # and replay names spell a path's `-` as `_` (pixman_pixman_access.c.o)
        if stem.endswith(".c"):
            stem = stem[:-2]
        alt = stem.replace("-", "_")
        hits = [o for o in objs if o in (stem + ".c.o", alt + ".c.o")
                or o.endswith("_" + stem + ".c.o") or o.endswith("_" + alt + ".c.o")]
        if not hits:
            sys.stderr.write(f"{lib}: no replay object for {m}\n")
            continue
        if len(hits) > 1:   # prefer the shortest path that is not a program dir
            hits = sorted(hits, key=len)[:1]
        p = f"{B}/replay/{pkg}/{hits[0]}"
        if p not in out:
            out.append(p)
print(" ".join(out))
