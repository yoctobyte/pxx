#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Compile every unit under lib/** as `program p; uses <unit>; begin end.`

Why this exists: `lib/pcl/tkhtmlview.pas` sat broken for its entire life —
398 lines that had never once compiled, on any binary including `pinned` —
because nothing in any gate ever named it. `make lib-test` exercises the units
its own smoke programs happen to reach, which is most of them and not all of
them, and "most" is exactly how a unit becomes permanently dead without anyone
noticing (bug-b-tkhtmlview-uses-named-arguments-pascal-does-not-have).

A `uses` of a unit compiles AND links its implementation, so this is a real
compile of the file, not an interface-only parse.

Exit 1 on any unit that fails outside the documented expectations below.
"""

import re
import concurrent.futures
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Units that legitimately do not compile as a bare `uses` on the host, each
# with the reason and the extra arguments that make them compile. A unit is
# only allowed in here when its failure is a property of the unit's PURPOSE,
# never because it is broken and unfixed.
EXTRA_ARGS = {
    # The thread PALs reach __pxxclone, which the compiler gates behind the
    # thread-safe runtime by REACH, not by use — the deliberate design recorded
    # in decide-threadsafe-gate-is-reach-based-not-use-based. Compiling them
    # without the flag is supposed to be a hard error.
    "palparallel": ["--threadsafe"],
    "palpthread": ["--threadsafe"],
    "palthreadobj": ["--threadsafe"],
    "palthread": ["--threadsafe"],
}

# Directories not on the default unit search path, so a bare `uses` cannot find
# them by name. They are reachable, just not implicitly.
EXTRA_UNIT_DIRS = ["lib/rtl/platform/esp"]

# The GTK3 include root, same definition as the Makefile, tools/gui_suite.sh and
# apps/ide/build.sh. lib/pcl/gtk3_c.h is `#include <gtk/gtk.h>` against the
# INSTALLED headers, gtk-2.0 is a default system include root and gtk-3.0 is
# not, and both answer to that spelling -- so without this every lib/pcl unit
# compiles against GTK2 while linking libgtk-3.so.0.
#
# Applied ONLY to units under lib/pcl, and that scoping is deliberate rather
# than tidiness: a `-I` in reach of a Pascal `uses` can capture the uses and
# turn it into a dynamic import
# (bug-a-a-c-include-path-captures-a-pascal-uses-and-emits-a-dynamic-import),
# and the units at risk are reached through the DEFAULT search path, which is not
# a flag and so cannot be reordered ahead of the include roots. Hence the
# explicit -Fu roots emitted before GTK3_INC in compile_one below.
#
# The trigger, measured on pinned v393 (which predates the compiler-side fix in
# 4576ad4d1, so the bug is live for anything built with this pin): ANY header on
# an -I root whose stem matches a Pascal unit can capture that unit's `uses`.
# GTK3_INC carries /usr/include/libpng16, and lib/rtl/png.pas collides with its
# png.h: with GTK3_INC and no -Fu, `uses png` then `PngLastError` is an
# undefined variable, while the same source with -Fulib/rtl first compiles.
#
# It does NOT take a header we ship, and an earlier version of this comment said
# it did. That was derived from a probe that only asked "does it build" -- and a
# bare `uses png` builds clean in BOTH orders, so the probe had two
# indistinguishable arms. The only tell without naming a symbol is the size
# line: procs=1046 for libpng's ~1000 declarations against procs=293 for the
# Pascal unit. A witness has to name a symbol only the Pascal unit provides.
GTK3_INC = [
    f for f in subprocess.run(
        ["pkg-config", "--cflags-only-I", "gtk+-3.0"],
        capture_output=True, text=True,
    ).stdout.split() if f
] or ["-I/usr/include/gtk-3.0/"]

# Units known to be broken, deliberately, with the ticket that owns them. This
# list must only ever shrink. An entry here is a promise that someone decided
# to leave it broken -- not a place to park a failure you did not want to fix.
# (tkhtmlview was the only entry this list ever held: written as though Pascal
# had keyword arguments, so it never compiled. It is now lib/pcl/tkhtmlview.py
# and the .pas is deleted -- feature-b-tkhtmlview-in-nilpy.)
KNOWN_BROKEN = {}


def compile_one(pxx, unit, src_path, tmpdir):
    # The probe program must NOT be named after the unit it uses: the resolver
    # searches the importing file's own directory first, so a `<unit>.pas` here
    # shadows the real lib unit and every probe compiles itself.
    src = os.path.join(tmpdir, f"zzprobe_{unit}.pas")
    out = os.path.join(tmpdir, f"zzprobe_{unit}")
    with open(src, "w") as f:
        f.write(f"program p;\nuses {unit};\nbegin end.\n")
    cmd = [pxx]
    for d in EXTRA_UNIT_DIRS:
        cmd.append("-Fu" + str(ROOT / d))
    if "lib/pcl/" in str(src_path).replace(os.sep, "/"):
        # Pascal roots BEFORE the include roots, and named explicitly rather
        # than left to the default search path: an include root ahead of the
        # Pascal search wins, and the default path cannot be moved ahead of a
        # flag because it is not one. See the GTK3_INC note above.
        cmd.append("-Fu" + str(ROOT / "lib" / "rtl"))
        cmd.append("-Fu" + str(ROOT / "lib" / "pcl"))
        cmd += GTK3_INC
    cmd += EXTRA_ARGS.get(unit, [])
    cmd += [src, out]
    p = subprocess.run(cmd, capture_output=True, text=True)
    return unit, p.returncode, (p.stdout + p.stderr)


# A failing unit's first three lines are usually its least informative three.
# Every GTK unit emits host-header warnings before its `{$ERROR ...}` fires, so
# a flat head-3 kept three warnings and discarded the one line naming the lane
# -- which mis-tracked the same job three times (see the crtl-reachability
# tickets). Rank error-bearing lines first, and never truncate silently.
DIAG_RE = re.compile(
    r"\berror\b|\bfatal\b|\{\$error|#error|\bundefined\b|\bcannot\b",
    re.I,
)


def failure_excerpt(out, limit=3):
    """Up to `limit` lines, error-bearing ones first, plus a dropped-count."""
    lines = [ln for ln in out.strip().splitlines() if ln.strip()]
    if not lines:
        return ["(no output)"]
    ranked = [ln for ln in lines if DIAG_RE.search(ln)]
    ranked += [ln for ln in lines if ln not in ranked]
    kept = ranked[:limit]
    # Restore source order so the excerpt still reads like the log it came from.
    kept.sort(key=lines.index)
    dropped = len(lines) - len(kept)
    if dropped > 0:
        kept.append(f"... {dropped} more line(s) not shown")
    return kept


def main():
    pxx = os.environ.get("PXX_STABLE") or str(
        ROOT / "stable_linux_amd64" / "default" / "pinned"
    )
    if not os.path.exists(pxx):
        print(f"lib-units: no compiler at {pxx}", file=sys.stderr)
        return 1

    units = sorted(
        {p.stem: p for p in (ROOT / "lib").rglob("*.pas")}.items()
    )
    if not units:
        print("lib-units: found no units under lib/ -- wrong root?", file=sys.stderr)
        return 1

    failures, unexpected_passes = [], []
    with tempfile.TemporaryDirectory() as tmpdir:
        workers = min(os.cpu_count() or 4, 16)
        with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as ex:
            futs = [ex.submit(compile_one, pxx, u, p, tmpdir) for u, p in units]
            for fut in concurrent.futures.as_completed(futs):
                unit, rc, out = fut.result()
                if rc != 0 and unit not in KNOWN_BROKEN:
                    failures.append((unit, out))
                elif rc == 0 and unit in KNOWN_BROKEN:
                    unexpected_passes.append(unit)

    for unit, out in sorted(failures):
        print(f"lib-units: FAIL {unit}")
        for line in failure_excerpt(out):
            print(f"    {line}")
    for unit in sorted(unexpected_passes):
        print(
            f"lib-units: {unit} compiles now but is listed KNOWN_BROKEN "
            f"({KNOWN_BROKEN[unit]}) -- drop the entry and close the ticket"
        )

    bad = len(failures) + len(unexpected_passes)
    if bad:
        return 1
    print(
        f"  lib-units: {len(units)} units compile "
        f"({len(KNOWN_BROKEN)} known-broken skipped)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
