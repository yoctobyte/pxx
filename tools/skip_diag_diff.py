#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Diff two `--diag-map` files: which skip rows changed their COMPILER DIAGNOSTIC.

WHY THE DIAGNOSTIC AND NOT THE VERDICT
--------------------------------------
`run_pascal_conformance.sh --retry-skips` re-attempts every skip-listed row and
reports the ones that now EXIT CLEAN. That instrument can only see a row which
started PASSING. A row whose VERDICT is still correct -- it genuinely fails --
while its REASON now names the wrong mechanism is invisible to it, by
construction.

Measured 2026-09-06 (frankS). A full retry sweep of 117 rows found SIX
exit-clean, all six already correctly dispositioned: ZERO stale reasons. The
same rows clustered by their FIRST DIAGNOSTIC found FIVE reasons naming a
mechanism that was not the cause:

  tmoperator2/3/9  blamed record management operators. Those are IMPLEMENTED --
                   `class operator Initialize/Finalize` fires for a local, in
                   order, with the right values. All three actually stop at
                   `undefined variable (InitializeArray)`, the System helper
                   that runs those operators over N elements. tmoperator9's
                   reason says "called for locals", which is the part that works.
  tgeneric78/79    blamed generics for a construct refused in a plain class with
                   no generics in it.

Two of the five had already misrouted their reader into generics; the tmoperator
three would have sent someone to implement a feature that is already there.

A NULL RESULT INHERITS THE APERTURE OF THE INSTRUMENT THAT PRODUCED IT. The
retry sweep's zero was a true answer to a different question, and quoting it
against a defect class that sweep cannot observe is the same error as quoting a
green from a guard that cannot fail.

WHAT THIS REPORTS, AND WHY THE THREE OUTCOMES STAY SEPARATE
-----------------------------------------------------------
  MOVED  in both maps, different diagnostic -- THE SIGNAL. The row still fails
         and fails for a different reason than when someone wrote its reason
         line, so that line is now suspect.
  NEW    only in the second map -- a row added to the skip list since.
  GONE   only in the first -- burned, renamed, or the run did not reach it.

Collapsing those into one "changed" count would make this an alarm rather than
an instrument: only MOVED is a claim about a reason being stale, and a sweep
that added rows would otherwise read as a pile of staleness.

A DIAGNOSTIC IS NOT NORMALISED BEYOND THE PATHS THE RUNNER ALREADY STRIPS.
Line numbers are deliberately KEPT. Stripping them would remove a real signal
(a diagnostic moving within a file) to reduce noise nobody has measured, and a
normalisation that discards signal on a guess is how an instrument stops being
able to fire. If line-number churn turns out to be real, strip it then and say
which run measured it.

Usage:
    tools/skip_diag_diff.py OLD.map NEW.map [--quiet-if-clean]

Exit 0 always: this reports, it does not gate. A moved diagnostic is a prompt to
re-read a reason, never a build failure.
"""
import argparse
import pathlib
import sys


def load(path: pathlib.Path) -> dict[str, str]:
    """name -> diagnostic. Comments and blank lines ignored.

    A malformed row (no tab) is DROPPED AND COUNTED rather than guessed at --
    see `read_map`, which returns the count so the caller can say so out loud.
    """
    out: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if "\t" not in line:
            continue
        name, diag = line.split("\t", 1)
        out[name.strip()] = diag.strip()
    return out


def read_map(path: pathlib.Path) -> tuple[dict[str, str], int]:
    rows = load(path)
    bad = 0
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if line.strip() and not line.lstrip().startswith("#") and "\t" not in line:
            bad += 1
    return rows, bad


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("old", type=pathlib.Path)
    ap.add_argument("new", type=pathlib.Path)
    ap.add_argument("--quiet-if-clean", action="store_true",
                    help="print nothing when no row moved (still prints NEW/GONE)")
    a = ap.parse_args()

    for p in (a.old, a.new):
        if not p.is_file():
            print(f"skip-diag-diff: no such map: {p}", file=sys.stderr)
            return 2

    old, old_bad = read_map(a.old)
    new, new_bad = read_map(a.new)

    # AN EMPTY MAP IS NOT A CLEAN MAP. --diag-map refuses to run without
    # --retry-skips for exactly this reason, but a map can still arrive empty
    # from an interrupted run, and "nothing moved" would be the wrong reading.
    if not old or not new:
        which = "old" if not old else "new"
        print(f"skip-diag-diff: the {which} map has NO ROWS. That is not "
              f"'nothing changed' -- it is 'nothing was measured'. Re-run "
              f"`run_pascal_conformance.sh --retry-skips --diag-map <path>` "
              f"and check it completed.")
        return 0

    if old_bad or new_bad:
        print(f"skip-diag-diff: {old_bad + new_bad} malformed row(s) ignored "
              f"(no TAB). Reported rather than guessed at: a row whose name and "
              f"diagnostic cannot be separated is not a row with an empty "
              f"diagnostic.")

    moved = [(n, old[n], new[n]) for n in sorted(old) if n in new and old[n] != new[n]]
    gone = sorted(n for n in old if n not in new)
    added = sorted(n for n in new if n not in old)

    if moved:
        print(f"MOVED: {len(moved)} skip row(s) still fail but now fail "
              f"DIFFERENTLY. Their reason lines were written against the old "
              f"diagnostic and are now suspect -- re-read each before quoting "
              f"it, and before routing anyone off it.")
        for name, o, n in moved:
            print(f"  {name}")
            print(f"      was: {o}")
            print(f"      now: {n}")
    elif not a.quiet_if_clean:
        shared = set(old) & set(new)
        print(f"MOVED: none of {len(shared)} shared row(s) changed diagnostic.")

    if added:
        print(f"NEW: {len(added)} row(s) only in the new map (added to the skip "
              f"list, or not attempted before) -- {', '.join(added)}")
    if gone:
        print(f"GONE: {len(gone)} row(s) only in the old map (burned, renamed, "
              f"or not reached this run) -- {', '.join(gone)}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
