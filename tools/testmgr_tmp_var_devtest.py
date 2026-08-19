#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: no job reaches /tmp through a SHELL VARIABLE.

`split_jobs` keeps a producer with its consumer by union-find over shared
literal `/tmp` paths, and testmgr privatizes those same literals so concurrent
runs do not collide. Both mechanisms are a filename scan (`tmp_re`), and both go
blind on a path spelled through a variable: `make -n` yields `/tmp/$bin`, which
`/tmp/[A-Za-z0-9_./+-]+` does not match at all.

The consequences are two, and the second outlives the first:

  * no shared token -> no merge -> a job runs a binary nothing built in its
    scratch dir (`test_nilpy_tkinter26: not found`, regression-test-nilpy-callbacks);
  * no privatization -> two concurrent runs share the file, so a wrong-output
    red is manufactured out of a collision.

This is the THIRD spelling of one class. The first two — a `.so` found by
soname, a bare-`/tmp` `LD_LIBRARY_PATH` consumer — were each closed by adding
one synthetic token for the spelling that had just been discovered. A
per-spelling token predicts the next one; this check does not have to
(bug-t-split-jobs-misses-a-tmp-path-reached-through-a-shell-variable).

Comment lines are excluded deliberately. The first draft of this check flagged
the very recipe that FIXED the callbacks case, because its explanatory comment
quotes the old `/tmp/$bin` spelling. A guard that trips on prose gets muted, and
a muted guard is not a guard — the same rule tstate_reader_devtest states.

Run: python3 tools/testmgr_tmp_var_devtest.py
"""
import importlib.util
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("tm", HERE / "testmgr.py")
tm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tm)

VAR_TMP = re.compile(r"/tmp/\$")

# Argued exceptions: a job here reaches /tmp through a variable and that is
# FINE, with the reason stated. Empty today — keep it that way if you can.
ALLOWED = {}

# KNOWN-OPEN: real instances with a ticket, listed so this guard can be green
# without the allowlist telling a lie. These PRINT on every run. Deleting a line
# here without fixing the recipe is the failure mode to watch for.
KNOWN = {
    "test-nilpy#src:examples/tk/tkinter_facade.npy":
        "the tk loop spells its BINARIES by full path (that was the callbacks "
        "fix) but still captures output to $(TESTTMP)/$$src.got, so the .got "
        "files are invisible to privatization and two concurrent runs share "
        "them — bug-n-tk-got-files-are-invisible-to-testmgr-privatization",
}


def main():
    offenders, known_seen = [], []
    for j in tm.generate("full"):
        sel = j.sel or j.name
        code = [l for l in j.lines if not l.strip().startswith("#")]
        hits = [l.strip() for l in code if VAR_TMP.search(l)]
        if not hits:
            continue
        if sel in ALLOWED:
            continue
        if sel in KNOWN:
            known_seen.append(sel)
            continue
        offenders.append((sel, hits[0][:120]))

    for sel in KNOWN:
        if sel in known_seen:
            print("  KNOWN-OPEN  %s\n              %s" % (sel, KNOWN[sel]))
        else:
            print("  ok   %s no longer reaches /tmp through a variable — remove "
                  "it from KNOWN and close its ticket" % sel)

    if offenders:
        print("\nFAIL: these reach /tmp through a shell variable, so split_jobs "
              "cannot merge them and testmgr cannot privatize them:")
        for sel, line in offenders:
            print("  %s\n    %s" % (sel, line))
        print("\nSpell the path in the recipe (the item list is the usual place) "
              "or add it to ALLOWED with a reason.")
        return 1
    print("\n  ok   no unlisted job reaches /tmp through a variable "
          "(%d known-open, %d allowed)" % (len(KNOWN), len(ALLOWED)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
