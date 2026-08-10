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

# Units known to be broken, deliberately, with the ticket that owns them. This
# list must only ever shrink. An entry here is a promise that someone decided
# to leave it broken -- not a place to park a failure you did not want to fix.
KNOWN_BROKEN = {
    # Written as though Pascal had keyword arguments; never compiled. The repo
    # owner chose to REPLACE it with a NilPy port rather than repair it, and to
    # leave the file broken meanwhile as the record of the question.
    "tkhtmlview": "feature-b-tkhtmlview-in-nilpy",
}


def compile_one(pxx, unit, tmpdir):
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
    cmd += EXTRA_ARGS.get(unit, [])
    cmd += [src, out]
    p = subprocess.run(cmd, capture_output=True, text=True)
    return unit, p.returncode, (p.stdout + p.stderr)


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
            futs = [ex.submit(compile_one, pxx, u, tmpdir) for u, _ in units]
            for fut in concurrent.futures.as_completed(futs):
                unit, rc, out = fut.result()
                if rc != 0 and unit not in KNOWN_BROKEN:
                    failures.append((unit, out))
                elif rc == 0 and unit in KNOWN_BROKEN:
                    unexpected_passes.append(unit)

    for unit, out in sorted(failures):
        print(f"lib-units: FAIL {unit}")
        for line in out.strip().splitlines()[:3]:
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
