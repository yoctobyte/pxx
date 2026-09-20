#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
#
# A compatibility shim must be REACHABLE. This asserts that nothing we ship
# shadows one.
#
# THE TRAP THIS EXISTS FOR IS UNSPRUNG, AND THAT IS WHY IT IS A GUARD RATHER
# THAN A FIX. `bug-n-a-same-named-rtl-unit-shadows-both-a-relative-import-and-a-
# mimic-shim` (arm 2) established that a NilPy `import X` prefers what we ship
# over a mimic shim, so writing `mimic_X.pas` for a module we already carry a
# unit X for produces a shim that is silently never reached. Measured
# 2026-09-20: the two sets are DISJOINT, so no shim is shadowed today. The trap
# springs the first time someone shims a module we already have -- and the
# owner's standing instruction is to craft a shim when a demo needs a library
# feature, so that is a live way to arrive here, not a hypothetical.
#
# NOTHING WOULD CATCH IT. The shadowed shim does not fail to compile; it simply
# never binds, and the program takes the unit instead. That is a silent wrong
# resolution, which is the class this tree spends the most on.
#
# THE CRITERION IS SET DISJOINTNESS AND CARRIES NO BASELINE COUNT, DELIBERATELY.
# A guard that records "23 shims and 137 units" is born stale: it reds on the
# next unit anyone adds, for no defect, and a guard that cries wolf on its first
# outside run teaches that it can be ignored. Disjointness is true or false
# regardless of how large either set grows.
#
# BOTH OURS-FIRST SUBSTITUTIONS ARE CHECKED, because there are exactly two and
# `--no-shims` exists to lift both (compiler/defs.inc, NoShims): the
# `mimic_<module>` fallback, and the curated `PyRtlUnitServesPython` list. A
# shim is shadowed by EITHER, so checking one would pass a tree where the other
# hides it.
#
#   tools/mimic_shadow_check.py [repo-root]     check the tree
#   tools/mimic_shadow_check.py --selftest .    prove the checker can fail, then check
#
# Exit 0 clean, 1 on a collision or a broken invocation.

import pathlib
import re
import sys


def unit_and_mimic_names(root: pathlib.Path):
    """Enumerate the two populations from the FILESYSTEM, not from a list."""
    lib = root / "lib"
    if not lib.is_dir():
        raise SystemExit(f"FAIL {lib} is not a directory -- this check cannot mean anything")
    mimic, units = {}, {}
    for p in sorted(lib.rglob("*.pas")):
        if p.stem.startswith("mimic_"):
            mimic.setdefault(p.stem[len("mimic_"):], p)
        else:
            units.setdefault(p.stem, p)
    if not mimic or not units:
        raise SystemExit("FAIL enumerated an empty population -- the check would pass vacuously")
    return mimic, units


def curated_python_units(root: pathlib.Path):
    """Read PyRtlUnitServesPython out of the COMPILER, so the two never drift.

    Derived from the tree being committed to rather than restated here: a list
    copied into this file would pin a report of the compiler instead of the
    compiler, and would be wrong the first time someone edits the function.
    """
    src = root / "compiler" / "pasparser_proc.inc"
    if not src.is_file():
        raise SystemExit(f"FAIL {src} is missing -- this check cannot mean anything")
    text = src.read_text(encoding="utf-8", errors="replace")
    m = re.search(r"function\s+PyRtlUnitServesPython\b.*?\bend;", text, re.S | re.I)
    if not m:
        raise SystemExit(
            "FAIL PyRtlUnitServesPython was not found in compiler/pasparser_proc.inc.\n"
            "     It is one of the two ours-first substitutions. If it was renamed or\n"
            "     moved, THIS CHECKER IS NOW BLIND TO HALF THE QUESTION -- fix it here\n"
            "     rather than deleting the arm."
        )
    names = set(re.findall(r"lo\s*=\s*'([^']+)'", m.group(0)))
    if not names:
        raise SystemExit("FAIL PyRtlUnitServesPython parsed to an EMPTY set -- a vacuous pass")
    return names


def check(root: pathlib.Path, verbose=True, report=True):
    mimic, units = unit_and_mimic_names(root)
    curated = curated_python_units(root)

    by_unit = sorted(set(mimic) & set(units))
    by_curated = sorted(set(mimic) & curated)

    if verbose:
        print(f"populations (enumerated from {root}):")
        print(f"  mimic shims                 : {len(mimic)}")
        print(f"  unit names under lib/       : {len(units)}")
        print(f"  PyRtlUnitServesPython names : {len(curated)}")

    # `report` is OFF for the selftest's deliberate collisions. Those are
    # EXPECTED failures, and printing the word FAIL for them puts it in a gate
    # log that everyone greps -- a guard whose positive control looks like its
    # own alarm teaches that the alarm can be ignored.
    rc = 0
    for name in by_unit:
        if report:
            print(f"FAIL mimic_{name}.pas is SHADOWED by the unit {units[name]}")
            print(f"     A NilPy `import {name}` takes the unit; the shim never binds.")
        rc = 1
    for name in by_curated:
        if report:
            print(f"FAIL mimic_{name}.pas is SHADOWED by PyRtlUnitServesPython('{name}')")
            print(f"     The curated list routes `import {name}` to our unit; the shim never binds.")
        rc = 1
    if rc and report:
        print("     Either drop the shim, or remove what shadows it -- and say which in the")
        print("     commit. A shim nobody can reach is worse than no shim: it reads as support.")
    elif verbose:
        print("ok: no shim is shadowed (both substitution sets are disjoint from the shims)")
    return rc


def _fake_tree(base: pathlib.Path, mimic, units, curated):
    """Build a throwaway tree the REAL check() will walk."""
    (base / "lib" / "rtl").mkdir(parents=True, exist_ok=True)
    (base / "compiler").mkdir(parents=True, exist_ok=True)
    for n in units:
        (base / "lib" / "rtl" / f"{n}.pas").write_text("unit x;\n")
    for n in mimic:
        (base / "lib" / "rtl" / f"mimic_{n}.pas").write_text("unit x;\n")
    arms = " or ".join(f"(lo = '{n}')" for n in curated) or "(lo = 'placeholderonly')"
    (base / "compiler" / "pasparser_proc.inc").write_text(
        f"function PyRtlUnitServesPython(const lo: AnsiString): Boolean;\n"
        f"begin\n  Result := {arms};\nend;\n")
    return base


def selftest():
    """Prove the checker can FAIL, in both directions, before trusting a pass.

    IT CALLS check() ON A REAL TREE RATHER THAN RE-IMPLEMENTING THE COMPARISON.
    The first version of this function asserted against a local copy of the
    set-intersection logic, which is a guard that cannot fail in the only way
    that matters: had check() itself broken, the duplicate would have kept
    printing PASS. A control has to exercise the path under test, not a
    lookalike of it.

    The synthetic names are drawn from the same question this checker answers --
    a shim name that collides -- rather than from some unrelated population that
    would pass either way. `widget` cannot appear in the real tree, so a pass
    here is never borrowed from the repo's own contents.
    """
    import tempfile

    ok = True
    with tempfile.TemporaryDirectory() as td:
        base = pathlib.Path(td)

        # MUST REJECT: a shim shadowed by a same-named unit.
        t = _fake_tree(base / "a", {"widget"}, {"widget", "gadget"}, {"sprocket"})
        if check(t, verbose=False, report=False) == 0:
            print("FAIL selftest: a shim shadowed by a UNIT was not reported")
            ok = False

        # MUST REJECT: a shim shadowed by the curated list.
        t = _fake_tree(base / "b", {"widget"}, {"gadget"}, {"widget"})
        if check(t, verbose=False, report=False) == 0:
            print("FAIL selftest: a shim shadowed by the CURATED LIST was not reported")
            ok = False

        # MUST ACCEPT: disjoint sets. Without this the checker could reject
        # everything and still pass the two rows above, which is a worse checker
        # and a green row.
        t = _fake_tree(base / "c", {"widget"}, {"gadget"}, {"sprocket"})
        if check(t, verbose=False, report=False) != 0:
            print("FAIL selftest: a clean tree was reported as a collision")
            ok = False

    print("selftest: the checker rejects both shadowing shapes and accepts a clean tree"
          if ok else "selftest: FAILED")
    return 0 if ok else 1


def main(argv):
    args = [a for a in argv[1:] if a != "--selftest"]
    root = pathlib.Path(args[0] if args else ".").resolve()
    if "--selftest" in argv[1:]:
        rc = selftest()
        if rc:
            return rc
    return check(root)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
