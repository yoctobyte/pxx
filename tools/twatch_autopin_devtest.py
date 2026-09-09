#!/usr/bin/env python3
"""Controls for twatch's auto-pin refusal gate, BOTH directions.

WHY BOTH. The bug that kept auto-pin in shadow for a month was a gate that
could not pass -- its evidence condition compared two disjoint sets of shas, so
no amount of waiting satisfied it. A refusal gate that always refuses is that
same bug wearing safety colours, and it would look responsible in review and in
the log. So this asserts a MUST-ALLOW case as hard as it asserts the refusals.

Every MUST-REFUSE row is drawn from the population the gate is actually about:
a real tier report shape, a real clone shape, and the specific ways a watcher
checkout drifts away from the sha it tested. A control from the wrong
population passes and certifies a broken instrument.

Run: python3 tools/twatch_autopin_devtest.py
"""
import os
import sys
import atexit
import shutil
import tempfile
import subprocess

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import twatch  # noqa: E402

SHA = "a" * 40
OTHER = "b" * 40
BIN_SHA = None          # filled in once the fake compiler exists


class FakeClone:
    """Enough of Clone for pin_refusal: a path, a branch, and dirty()."""

    def __init__(self, path, dirt=""):
        self.path = path
        self.branch = "master"
        self._dirt = dirt

    def dirty(self):
        return self._dirt


def make_repo(head=SHA, armed=True, binary=b"COMPILER-BYTES"):
    """A directory shaped like a watcher clone at a given HEAD."""
    d = tempfile.mkdtemp(prefix="autopin-devtest-")
    # Reap it. mkdtemp with no rmtree is the family that took seven dark for ten
    # hours on /tmp inode exhaustion (2026-09-07): the box was 9% full by BYTES
    # and had 8 free inodes of 1048576. Each make_repo() is a git init plus a
    # commit, so a run leaves eight repos behind, and this file runs in every
    # full tier. atexit rather than a finally: the controls deliberately keep
    # their repos alive across the whole run to compare them.
    atexit.register(shutil.rmtree, d, ignore_errors=True)
    subprocess.run(["git", "init", "--quiet", d], check=True)
    subprocess.run(["git", "-C", d, "config", "user.email", "t@t"], check=True)
    subprocess.run(["git", "-C", d, "config", "user.name", "t"], check=True)
    os.makedirs(os.path.join(d, "compiler"), exist_ok=True)
    with open(os.path.join(d, "compiler", "pascal26"), "wb") as f:
        f.write(binary)
    if armed:
        os.makedirs(os.path.join(d, twatch.TSTATE_REL), exist_ok=True)
        open(os.path.join(d, twatch.PIN_ARMED_REL), "w").write("armed\n")
    subprocess.run(["git", "-C", d, "add", "-A"], check=True)
    subprocess.run(["git", "-C", d, "commit", "--quiet", "-m", "x"], check=True)
    real = subprocess.run(["git", "-C", d, "rev-parse", "HEAD"],
                          capture_output=True, text=True, check=True).stdout.strip()
    return d, real


def report(**over):
    r = {"tier": "full", "verdict": "GREEN", "jobs": {"a": "PASS"},
         "compiler_sha256": BIN_SHA, "compiler_changed_mid_run": False}
    r.update(over)
    return r


def main():
    global BIN_SHA
    d0, head0 = make_repo()
    BIN_SHA = twatch._sha256_file(os.path.join(d0, "compiler", "pascal26"))

    bad = 0

    # ---- MUST ALLOW: every guard satisfied. If this fails the gate is the
    # ---- unsatisfiable kind and auto-pin is back where it started.
    d, head = make_repo()
    BIN_SHA = twatch._sha256_file(os.path.join(d, "compiler", "pascal26"))
    why = twatch.pin_refusal(FakeClone(d), head, report())
    ok = (why == "")
    bad += not ok
    print("%-12s MUST ALLOW  clean armed run at the tested sha%s"
          % ("ok" if ok else "*** FAIL ***", "" if ok else "  -> refused: " + why))

    # ---- MUST REFUSE, one row per guard.
    cases = []

    d, head = make_repo(armed=False)
    BIN_SHA = twatch._sha256_file(os.path.join(d, "compiler", "pascal26"))
    cases.append(("not armed", FakeClone(d), head, report()))

    d, head = make_repo()
    BIN_SHA = twatch._sha256_file(os.path.join(d, "compiler", "pascal26"))
    # HEAD moved: the tier tested SHA, the checkout is somewhere else. This is
    # the guard a naive arming omits, because on a quiet tree it always passes.
    cases.append(("HEAD moved off the tested sha", FakeClone(d), OTHER, report()))

    d, head = make_repo()
    BIN_SHA = twatch._sha256_file(os.path.join(d, "compiler", "pascal26"))
    cases.append(("dirty tree", FakeClone(d, dirt=" M compiler/x.inc"), head,
                  report()))

    d, head = make_repo()
    BIN_SHA = twatch._sha256_file(os.path.join(d, "compiler", "pascal26"))
    cases.append(("binary is not the one tested", FakeClone(d), head,
                  report(compiler_sha256="f" * 64)))

    d, head = make_repo()
    BIN_SHA = twatch._sha256_file(os.path.join(d, "compiler", "pascal26"))
    cases.append(("compiler changed mid-run", FakeClone(d), head,
                  report(compiler_changed_mid_run=True)))

    d, head = make_repo()
    BIN_SHA = twatch._sha256_file(os.path.join(d, "compiler", "pascal26"))
    cases.append(("no measurement: no compiler_sha256", FakeClone(d), head,
                  report(compiler_sha256=None)))

    d, head = make_repo()
    BIN_SHA = twatch._sha256_file(os.path.join(d, "compiler", "pascal26"))
    cases.append(("no measurement: zero jobs", FakeClone(d), head,
                  report(jobs={})))

    for label, clone, sha, rep in cases:
        why = twatch.pin_refusal(clone, sha, rep)
        ok = bool(why)
        bad += not ok
        print("%-12s MUST REFUSE %-34s %s"
              % ("ok" if ok else "*** FAIL ***", label,
                 ("-> " + why) if why else "-> ALLOWED IT"))

    total = 1 + len(cases)
    if bad:
        print("\n*** %d of %d controls FAILED ***" % (bad, total))
        return 1
    print("\nall %d controls pass (1 allow, %d refuse)" % (total, len(cases)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
