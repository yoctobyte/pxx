#!/usr/bin/env python3
"""Replay objects for Xfbdev: every member of the archives on gcc's link line
(kdrive/fbdev cwd), mapped to $PATHB_WORK/replay/tinyx/<dir_with_underscores>_<src>.c.o"""
import os, subprocess, sys
B = os.environ["PATHB_WORK"]; T = f"{B}/src/tinyx"; R = f"{B}/replay/tinyx"
arcs = ["kdrive/fbdev/libfbdev.a", "dix/.libs/libdix.a", "kdrive/src/libkdrive.a",
        "kdrive/linux/liblinux.a", "fb/.libs/libfb.a", "mi/.libs/libmi.a",
        "xfixes/.libs/libxfixes.a", "Xext/.libs/libXext.a", "dbe/.libs/libdbe.a",
        "render/.libs/librender.a", "randr/.libs/librandr.a", "damageext/.libs/libdamageext.a",
        "miext/damage/.libs/libdamage.a", "miext/shadow/.libs/libshadow.a", "os/.libs/libos.a",
        "kdrive/src/libkdrivestubs.a"]
out = [f"{R}/kdrive_fbdev_fbinit.c.o"]
for a in arcs:
    d = os.path.dirname(a).replace("/.libs", "")
    for m in subprocess.run(["ar", "t", f"{T}/{a}"], capture_output=True, text=True, check=True).stdout.split():
        stem = m[:-2]
        for cand in (stem, stem.split("-", 1)[-1]):   # libtool prefixes some members (libdix_la-foo.o)
            o = f"{R}/{d.replace('/', '_')}_{cand}.c.o"
            if os.path.exists(o):
                if o not in out: out.append(o)
                break
        else:
            # built from another directory (kdrive/src compiles ../../mi/miinitext.c)
            hits = [f for f in os.listdir(R) if f.endswith(f"_{stem}.c.o")]
            if len(hits) == 1 and f"{R}/{hits[0]}" not in out: out.append(f"{R}/{hits[0]}")
            else: sys.stderr.write(f"missing: {a} {m}\n")
print(" ".join(out))
