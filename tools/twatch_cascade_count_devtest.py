#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: an open CASCADE reports how much is STILL red, not how much it swept.

A cascade entry is opened by one sweep and closed only when EVERY job it swept
is passing again (`reg_open`). Those two facts put a number on the wrong side of
a decision: for the whole life of the entry, `--status` printed the size of the
original sweep. Measured 2026-08-20 on plexus -- `open CASCADE: 13 jobs` while 4
of the 13 had recovered and 9 were red. Nothing about the line was false; it
answered "how big was the sweep" where the reader was asking "how much do I have
to go fix", and the gap between those grows every time a job recovers.

Same shape as the pin verify's red count the night before -- a true fact about
the wrong subject -- so the guards here are aimed at the same three ways it can
come back:

  1. The line prints the still-red count. This is the ticket.
  2. It prints the swept total BESIDE it, because the still-red number alone is
     a census the ledger cannot actually take (see `gone` in cascade_still_red)
     and a ratio says so.
  3. The predicate stays reg_open's. A status line that closed a job the ledger
     still counts open would be a second opinion in the one place two opinions
     are indistinguishable from a bug -- so `skip` is PASSLIKE here exactly as
     it is there, and an unreported job counts red exactly as it does there.

Run: python3 tools/twatch_cascade_count_devtest.py
"""

import io
import json
import os
import subprocess
import sys
import tempfile
import datetime
from contextlib import redirect_stdout

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import twatch  # noqa: E402

fails = []
ran = []


def check(cond, what, detail=""):
    """Record one guard. `cond` may be a callable, and should be when its
    subject could raise -- a raise then becomes a named FAIL instead of ending
    the file and reading as a clean run under a neuter."""
    ran.append(what)
    if callable(cond):
        try:
            cond = cond()
        except Exception as e:                                      # noqa: BLE001
            cond, detail = False, "RAISED %s: %s" % (type(e).__name__, e)
    print("  %-4s %-62s %s" % ("PASS" if cond else "FAIL", what, detail))
    if not cond:
        fails.append(what)


# The real 2026-08-20 cascade, by its own numbers: 13 swept, 4 recovered.
SWEPT = ["lib-test#src:test/lib_mimic_xml_etree_elementtree.npy",
         "test-nilpy#src:test/test_cpyext_args_errors.npy",
         "test-nilpy#src:test/test_cpyext_containers.npy",
         "test-nilpy#src:test/test_cpyext_cython.npy",
         "test-nilpy#src:test/test_cpyext_errformat.npy",
         "test-nilpy#src:test/test_cpyext_hello.npy",
         "test-nilpy#src:test/test_cpyext_markupsafe.npy",
         "test-nilpy#src:test/test_nilpy_callable_to_str_param_fails.npy",
         "test-nilpy#src:test/test_nilpy_kwarg_overload_set.npy",
         "test-nilpy#src:test/test_nilpy_qualified_proc_omitted_default.npy",
         "test-nilpy#src:test/test_nilpy_tobject_member_via_local.npy",
         "test-riscv32#src:test/test_cross_float.pas",
         "tools-devtest#00"]
RECOVERED = SWEPT[8:11] + [SWEPT[12]]          # 4 pass
STILL = [j for j in SWEPT if j not in RECOVERED]
BAD = "21f098e32a95" + "0" * 28

ENTRY = {"job": "cascade@" + BAD, "cascade": SWEPT, "bad": BAD,
         "good": None, "range": ["c" * 40] * 261}


def jobs(passing=(), skipping=(), missing=()):
    m = {j: "fail" for j in SWEPT if j not in missing}
    for j in passing:
        m[j] = "pass"
    for j in skipping:
        m[j] = "skip"
    return {k: v for k, v in m.items() if k not in missing}


def csr(**kw):
    return twatch.cascade_still_red(ENTRY, {"jobs": jobs(**kw)})


print("the count follows the damage, not the sweep")
check(lambda: csr(passing=RECOVERED) == (9, 13),
      "4 of 13 recovered -> 9 still red, 13 swept",
      "the shipped line said 13; this is the whole ticket")
check(lambda: csr() == (13, 13),
      "nothing recovered -> 13 of 13, printed as a ratio anyway",
      "no branch to the bare count: that is the form that lied")
check(lambda: csr(passing=SWEPT) == (0, 13),
      "everything recovered -> 0 of 13",
      "reg_open closes the entry here, so status should never print it")

print("\nthe predicate is reg_open's, or the two disagree in public")
check(lambda: csr(skipping=RECOVERED) == (9, 13),
      "a skip closes a job here exactly as PASSLIKE does in reg_open",
      "a skip is not proof of a fix, but it must not gate either")
check(lambda: csr(missing=RECOVERED) == (13, 13),
      "a job the map never mentions counts RED, as reg_open defaults it",
      "status cannot compute `gone`; erring open matches the open entry")
check(lambda: twatch.cascade_still_red(ENTRY, {}) == (13, 13),
      "an empty state counts every swept job red rather than raising")
check(lambda: twatch.cascade_still_red(
          {"cascade": [], "bad": BAD}, {"jobs": {}}) == (0, 0),
      "an empty sweep is (0, 0), not a division or a crash")


def agree(passing):
    """The one property that matters: same verdict as the ledger, always."""
    st = {"jobs": jobs(passing=passing)}
    n = twatch.cascade_still_red(ENTRY, st)[0]
    return (n > 0) == twatch.reg_open(ENTRY, st["jobs"])


check(lambda: all(agree(SWEPT[:k]) for k in range(len(SWEPT) + 1)),
      "'still red > 0' matches reg_open at every recovery depth 0..13",
      "a status line that closed what the ledger holds open is a second bug")


print("\nend to end: the line --status actually prints")


def ago(minutes):
    t = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=minutes)
    return t.strftime("%Y-%m-%dT%H:%M:%SZ")


class Fixture:
    def __init__(self):
        self.d = tempfile.mkdtemp(prefix="cascade-count-")
        self._git("init", "-q", "-b", "master", ".")
        self._git("config", "user.email", "t@example.invalid")
        self._git("config", "user.name", "t")
        with open(os.path.join(self.d, "f"), "w") as f:
            f.write("a\n")
        self._git("add", "f")
        self._git("commit", "-qm", "one")
        self.head = self._out("rev-parse", "HEAD")
        self.tdir = os.path.join(self.d, "td")
        os.makedirs(self.tdir)

    def _git(self, *a):
        subprocess.run(("git",) + a, cwd=self.d, check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def _out(self, *a):
        return subprocess.run(("git",) + a, cwd=self.d, check=True,
                              capture_output=True, text=True).stdout.strip()

    def run(self, passing):
        st = {"host": "testbox",
              "last": {"sha": self.head, "verdict": "GREEN", "tier": "native",
                       "date": ago(5)},
              "last_full": {"sha": self.head, "verdict": "RED", "tier": "full",
                            "date": ago(30)},
              "jobs": jobs(passing=passing),
              "open_regressions": [ENTRY]}
        with open(os.path.join(self.tdir, "testbox.json"), "w") as f:
            json.dump(st, f)
        buf = io.StringIO()
        with redirect_stdout(buf):
            twatch.status(self.d, 60, tdir=self.tdir, ref="HEAD", fetch=False)
        for ln in buf.getvalue().splitlines():
            if "CASCADE" in ln:
                return ln
        return ""


F = Fixture()
LINE = F.run(RECOVERED)
check(bool(LINE), "an open cascade still produces a line",
      "the fix must not silence the entry it renumbers")
check(lambda: "9 of 13" in LINE, "...reading '9 of 13', the live numbers",
      LINE.strip() or "(no line)")
check(lambda: "13 job" not in LINE and "13 swept" not in LINE.split("of")[0],
      "...and NOT the bare swept count that shipped",
      "'13 jobs' is the exact string this ticket exists to remove")
check(lambda: "still red" in LINE, "...saying what the 9 are")
check(lambda: BAD[:12] in LINE and "261 in range" in LINE,
      "...keeping the bisect facts the line already carried",
      "renumbering must not cost the reader the suspect range")
none_gone = F.run([])
check(lambda: "13 of 13" in none_gone,
      "a cascade with nothing recovered prints 13 of 13, not '13 jobs'",
      none_gone.strip() or "(no line)")

print()
if fails:
    print("FAILED %d of %d check(s):" % (len(fails), len(ran)))
    for f in fails:
        print("  - " + f)
    sys.exit(1)
print("all %d cascade-count guards green" % len(ran))
