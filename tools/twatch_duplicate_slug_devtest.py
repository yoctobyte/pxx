#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: one slug in two folders is open and closed at once.

The open half is indistinguishable from a live ticket in every instrument
except a whole-tree comparison, so it inflates the exact open-bug count the
owner wants driven to zero, and `ready --track A` keeps offering it.

TWO MECHANISMS, ARRIVING FROM OPPOSITE DIRECTIONS, four hours apart:

  * `364c35bf2` — the watcher closed a regression as a pure ADD (49
    insertions, one file, no rename), leaving the backlog stub in place. Its
    other close path, `54964cd97`, is a clean `backlog => done` rename. The
    close paths are not uniform and nothing compares them.
  * `dae71ffb2` — a RESURRECTION. A peer added 67 lines to a `backlog/` path
    four minutes after a rename had removed it. The peer's tree predated the
    rename, git re-created the file at the old path, and the rebase merged
    silently because the two commits touched different paths. Nothing failed
    and nothing warned.

THE POSITIVE CONTROL RUNS AGAINST THOSE TWO REAL TREES, not against a
reconstruction of them, which is why duplicate_slugs() takes a `rev`. A guard
for a rare condition is exactly the guard most likely to be unfailable without
anyone noticing — on a clean tree it prints nothing forever, which is also what
a broken one prints.

Run: tools/twatch_duplicate_slug_devtest.py   (exit 0 = pass)
"""
import importlib.util
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
spec = importlib.util.spec_from_file_location("tw", os.path.join(HERE, "twatch.py"))
tw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tw)

FAILS = []


def check(name, cond, detail=""):
    if cond:
        print("  ok   %s" % name)
    else:
        print("  RED  %s" % name)
        FAILS.append("%s\n      %s" % (name, detail))


def have(rev):
    return subprocess.run(["git", "cat-file", "-e", rev + "^{commit}"],
                          cwd=ROOT, capture_output=True).returncode == 0


def synthetic(dirs):
    """A tree with the given {folder: [slug, ...]}. -> root path."""
    d = tempfile.mkdtemp(prefix="dupslug-devtest-")
    for folder, slugs in dirs.items():
        full = os.path.join(d, "devdocs", "progress", folder)
        os.makedirs(full, exist_ok=True)
        for s in slugs:
            open(os.path.join(full, s), "w").write("x\n")
    return d


def main():
    print("twatch duplicate-slug devtest")

    # --- POSITIVE CONTROLS, against the real historical trees ---
    # Skipped rather than passed if the shas are unreachable: a control that
    # silently drops out is the failure this file exists to refuse.
    for rev, want in (("364c35bf2", "regression-test-core-test-nested-class-"
                                    "type-scoping.md"),
                      ("dae71ffb2", "regression-test-emit-obj-c-obj-data-"
                                    "dup-a.md")):
        if not have(rev):
            check("POSITIVE CONTROL %s reachable" % rev, False,
                  "sha not in this clone — the control did not run, which is "
                  "NOT a pass")
            continue
        got = tw.duplicate_slugs(ROOT, rev)
        check("POSITIVE CONTROL: %s reports its duplicate" % rev,
              want in got,
              "expected %s in %s" % (want, sorted(got)))

    # --- the shapes, synthetically, so each branch is proven to fire ---
    d = synthetic({"backlog": ["a.md"], "done": ["a.md"]})
    check("a slug in backlog/ and done/ is reported",
          "a.md" in tw.duplicate_slugs(d))

    d = synthetic({"backlog": ["a.md"], "working": ["a.md"]})
    check("two OPEN folders count too — no open/terminal classification",
          "a.md" in tw.duplicate_slugs(d),
          "the broader net is the whole point; a classification here would be "
          "a judgement this check cannot verify")

    d = synthetic({"backlog": ["a.md"], "done": ["b.md"]})
    check("distinct slugs are not reported", not tw.duplicate_slugs(d))

    d = synthetic({"backlog": ["README.md"], "done": ["README.md"]})
    check("README is not a ticket", not tw.duplicate_slugs(d))

    d = synthetic({"backlog": ["a.md"], "tstate": ["a.md"]})
    check("a non-ticket directory does not make a duplicate",
          not tw.duplicate_slugs(d),
          "tstate/, fixtures/ and patches/ hold no tickets")

    d = synthetic({"backlog": ["a.md"], "done": ["a.txt"]})
    check("only .md files are tickets", not tw.duplicate_slugs(d))

    # --- and the live board, which is the reason the guard exists ---
    live = tw.duplicate_slugs(ROOT)
    check("the working tree has no duplicate slug", not live,
          "live duplicates: %s" % sorted(live))

    print("twatch duplicate-slug OK" if not FAILS
          else "twatch duplicate-slug BROKEN")
    for f in FAILS:
        print("  " + f)
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
