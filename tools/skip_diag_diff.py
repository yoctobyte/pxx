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

RUN IN ANGER, 2026-09-06 (frankS): pinned v404 vs HEAD 67d173f13, both
--retry-skips --diag-map, 114 rows each side. 9 MOVED, 0 NEW, 0 GONE, no
sentinel rows -- and it corrected four reasons the exit-code sweep cannot see.

FOUR OF THE NINE MOVED OFF ONE SHARED BLOCKER, and that is the class worth
naming. `undefined variable (erroraddr)` -- a pinned-RTL gap at line 82 -- was
the first diagnostic for texception3, tobject1, tstring4 and others. HEAD fixed
it, and those rows showed their REAL blockers for the first time. THREE OF THEM
STILL FAIL, so the exit-code channel saw nothing at all while the mechanism
changed completely.

  A SHARED BLOCKER MAKES A WHOLE GROUP'S REASONS UNVERIFIABLE AT ONCE, AND
  CLEARING IT UN-HIDES THEM ALL IN ONE COMMIT.

That is the opposite of the failure mode this tool was built for: not a reason
going stale one row at a time, but a batch of reasons that were never testable
becoming testable together. It also means a MOVED count spikes after an RTL or
pin change for a reason that is not decay -- read the diagnostics, not the count.

THE DIAGNOSTIC CAN RETIRE A REASON. IT CAN NEVER RETIRE A TAG. (frankS's rule,
and the reason four corrected reasons kept their `wontfix:`/`gap:` labels.) A
first-error diagnostic proves nothing about the lines after it, so "the stated
premise is false" and "the disposition is wrong" are different claims and only
the first is in evidence. tclass13 is the case: tagged wontfix on "needs FPC
typinfo/RTTI", and `GetEnumName(TypeInfo(TCol), Ord(cGreen))` was MEASURED to
print byte-identically to fpc -- the premise is dead, and whether the row should
still be skipped is a separate question nobody has answered.

A NEGATIVE THAT BOUNDS THE WORK: of the 29 rows compiling clean at HEAD, every
single reason already said so ("compiles and runs", "accepts-invalid",
"dialect-pass"). Nobody needs to audit that set. The mismatches cluster where
they clustered before.

A TRUNCATED MAP IS THE WORST INPUT TO THIS TOOL AND IT CANNOT DEFEND ITSELF.
An interrupted run leaves a map that is well-formed, parses, and is correct row
by row -- the rows it never reached simply come back as GONE. `if not old or not
new` below catches the EMPTY map; nothing here can distinguish a half map from a
complete one. So the defence lives in the producer: since 2026-09-06
`run_pascal_conformance.sh` writes `<path>.partial` and renames only after its
summary line, so a killed run leaves NO map rather than a short one. If you hand
a map to this tool from anywhere else, guarantee completeness at that call site.

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
Line numbers are deliberately KEPT -- and that is now MEASURED, not reasoned.
frankS diffed two full retry sweeps, 2026-09-06, 86 shared rows:

    81 of 86 identical, line number included
     5 differed
     0 pure line-number churn -- every single difference was a MESSAGE change

So the noise this normalisation would have removed does not exist, and it would
have cost the one thing worth having. tgenfunc8 is the case that settles it:
SAME line 26, DIFFERENT message. A tool keying on the line -- or on any
positional key -- misses that row entirely, which is the second argument for
comparing the full string. tarray3 is the other end, 13 -> 129: a diagnostic
that moved 116 lines within a fixed file, which is a mechanism change and
exactly the signal wanted.

CAVEAT, AND IT IS DOING THE WORK IN THAT 81. The corpus sources are FIXED, so a
line number only moves when the compiler starts failing at a different POINT in
the same file. Point this tool at a source tree that CHANGES and the
measurement does not transfer: there, an edit above the failure moves every
line number below it and the churn is real. Re-measure before trusting the
count in that setting.

TWO VALUES IN A MAP ARE NOT DIAGNOSTICS AND THEY ARE HANDLED SEPARATELY.
The runner writes `<compile failed with no error: line> ...` and `<exit 0 but
no 'ok:' line ...>` when the compile produced neither a diagnostic nor an `ok:`
line. Those are facts about the RUN, not about the row -- frankS lost a sweep
to exactly this when the fpc side wrote its binaries elsewhere and every row
came back rc=127, which read as a measurement. A move into one of them is still
reported (a row that started CRASHING instead of diagnosing is a real finding),
but it is MARKED, and if every moved row moved into one, this says so: that is
the shape of a broken run, and reading it as 86 changed mechanisms is the
failure mode this whole tool exists to avoid.

WHAT `<compiles clean>` DOES NOT CLAIM. It means OUR compiler accepted the file
and printed its `ok:` line. It does NOT mean we agree with fpc about it: frankS
measured 2026-09-06 that 360 of the 1447 suite files carry an `{$ifdef FPC}`,
and pxx does not define FPC outside --mimic-fpc, so on those rows the two
compilers are given DIFFERENT PROGRAMS. This tool is unaffected -- it compares
our diagnostics to our earlier diagnostics, which is self-consistent whichever
arm we took -- but a reader who takes a `<compiles clean>` row as a burn
candidate is making the stronger claim, and for a row with a live FPC arm that
claim is not in evidence. tarray3 is one such row.

Usage:
    tools/skip_diag_diff.py OLD.map NEW.map [--quiet-if-clean]

Exit 0 always: this reports, it does not gate. A moved diagnostic is a prompt to
re-read a reason, never a build failure.
"""
import argparse
import pathlib
import sys


# The runner's two non-diagnostic sentinels. Kept as prefixes because each
# carries the run's own first output line after it.
UNMEASURED_PREFIXES = ("<compile failed with no error: line>",
                       "<exit 0 but no 'ok:' line")


def _unmeasured(diag: str) -> bool:
    """True for a value that records a RUN failure rather than a diagnostic."""
    return diag.startswith(UNMEASURED_PREFIXES)


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

    # A RUN-LEVEL FAILURE WEARS THE SHAPE OF A FLEET OF MOVED ROWS. No
    # threshold, because no threshold has been measured -- the tell is the
    # SHAPE: every row that moved, moved into a value that means "not
    # measured".
    into_unmeasured = [m for m in moved if _unmeasured(m[2])]
    run_is_suspect = bool(moved) and len(into_unmeasured) == len(moved) and len(moved) > 1

    if moved:
        print(f"MOVED: {len(moved)} skip row(s) still fail but now fail "
              f"DIFFERENTLY. Their reason lines were written against the old "
              f"diagnostic and are now suspect -- re-read each before quoting "
              f"it, and before routing anyone off it.")
        for name, o, n in moved:
            mark = "  <-- NOT A DIAGNOSTIC" if _unmeasured(n) else ""
            print(f"  {name}{mark}")
            print(f"      was: {o}")
            print(f"      now: {n}")
        if run_is_suspect:
            print(f"  !! EVERY one of those {len(moved)} rows moved into a value "
                  f"that means the compile produced no diagnostic at all. That "
                  f"is the shape of a BROKEN RUN, not of {len(moved)} changed "
                  f"mechanisms -- check the compiler and the paths the sweep "
                  f"used, and re-run before re-reading a single reason line.")
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
