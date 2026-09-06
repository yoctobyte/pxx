#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: reap_stale() must never delete the CURRENT run's scratch dir.

The pid reap_stale() acts on comes out of the LOCK FILE. lock_state() already
says why that pid is not an identity -- "pids get reused" -- and reap_stale
turned it straight into `rmtree("%s/testmgr-scratch-%d" % (TESTTMP, pid))`. A
stale lock naming pid P, plus a live run the kernel has handed P, means that
path IS the live run's RUN_TMP.

WHAT THAT LOOKS LIKE FROM THE OUTSIDE is the thing worth guarding against: the
compiler writes an artifact and prints `ok: <path> [code=...]`, and a later step
of the SAME recipe says `ld: cannot find <path>: No such file or directory`.
Nothing errors. The red lands in whatever subject happened to own the file, and
it reads as a codegen defect in that subject -- which is how
regression-test-emit-obj-c-obj-data-import-2 was first laned.

THIS IS A DEFENSIVE GUARD AND THE FILE SAYS SO. Call ordering makes it
unreachable-with-harm today: acquire_lock() reaps before the run has populated
its scratch. That is a property of the CALLERS, not of reap_stale, and it is
exactly the kind of fact that is true until someone adds a second call site.

Two sibling cleanup paths had this predicate already and disagreed on it:

    kill_run()          if pid in (os.getpid(), os.getppid()): refuse
    sweep_orphan_tmp()  if pid == os.getpid(): continue
    reap_stale()        (nothing)

Run: tools/testmgr_reap_self_devtest.py   (exit 0 = pass)
"""
import importlib.util
import os
import sys
import tempfile

FAILS = []


def check(label, got, want):
    if got != want:
        FAILS.append("%s: got %r, want %r" % (label, got, want))
        print("  FAIL %s: got %r, want %r" % (label, got, want))
    else:
        print("  ok   %s" % label)


def load_testmgr(testtmp):
    """Import testmgr with TESTTMP pointed at a scratch root we own.

    TESTTMP is read at import time, so it must be set BEFORE the module object
    exists -- setting it afterwards would leave the module's own derivations
    pointing at the real /tmp and this devtest would then be measuring the
    wrong directory while still passing.
    """
    os.environ["TESTTMP"] = testtmp
    here = os.path.dirname(os.path.abspath(__file__))
    spec = importlib.util.spec_from_file_location(
        "testmgr_under_test", os.path.join(here, "testmgr.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main():
    with tempfile.TemporaryDirectory(prefix="reapself-") as root:
        tm = load_testmgr(root)

        check("module read our TESTTMP", tm.TESTTMP, root)

        # reap_stale unlinks the lock; point it at our own so a real concurrent
        # run's lock is never touched by this devtest.
        tm.LOCK_PATH = os.path.join(root, "run.lock")

        # (1) THE GUARD: a scratch dir named for OUR pid must survive.
        mine = "%s/testmgr-scratch-%d" % (root, os.getpid())
        os.makedirs(mine, exist_ok=True)
        artifact = os.path.join(mine, "cods_imp_x64.o")
        with open(artifact, "w") as f:
            f.write("an object a live recipe is about to link")
        tm.reap_stale({"pid": os.getpid(), "heartbeat": 0})
        check("our own scratch survives", os.path.isfile(artifact), True)

        # (2) THE POSITIVE CONTROL, drawn from the population the guard is
        # about: a scratch dir named for a pid that is NOT ours and NOT alive
        # must still be reaped, or the guard above is just a disabled reaper.
        dead = find_dead_pid()
        if dead is None:
            FAILS.append("could not find a dead pid to build the control on")
            print("  FAIL no dead pid available — control not run")
        else:
            theirs = "%s/testmgr-scratch-%d" % (root, dead)
            os.makedirs(theirs, exist_ok=True)
            with open(os.path.join(theirs, "stale.o"), "w") as f:
                f.write("left by a run that is gone")
            tm.reap_stale({"pid": dead, "heartbeat": 0})
            check("a dead run's scratch is still reaped",
                  os.path.isdir(theirs), False)

    if FAILS:
        print("\ntestmgr_reap_self_devtest: %d FAILURE(S)" % len(FAILS))
        for f in FAILS:
            print("  " + f)
        return 1
    print("\ntestmgr_reap_self_devtest: OK")
    return 0


def find_dead_pid():
    """A pid that is not running, so the control exercises the reaping path."""
    for candidate in range(400000, 400400):
        if candidate in (os.getpid(), os.getppid()):
            continue
        try:
            os.kill(candidate, 0)
        except ProcessLookupError:
            return candidate
        except OSError:
            continue
    return None


if __name__ == "__main__":
    sys.exit(main())
