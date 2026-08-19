#!/usr/bin/env python3
"""Devtest: `--status` answers "is the PIN sound?", not only "is HEAD tested?".

Those are different questions with different answers, and until 2026-08-19
`--status` answered only the second. Every line it printed came off `last_full`
-- the newest tier on the newest tree. A peer held pin v367 for an hour and a
half on "there is still no full tier at v366" while a completed full tier at the
pinned sha sat one key away in the same file, carrying exactly the verdict they
were waiting for. The data existed; the summary implied its absence.

The second half is the caveat that makes those reds readable. A pin sits at a
frozen sha while master runs ahead, so "job X is red in pin verify" and "job X
is green at HEAD" are routinely BOTH true -- they are statements about different
trees. Measured the same day: `tools-devtest#00` was red in the v366 verify at
cabb5d598 and green at HEAD, because the fix landed 27 commits after the
verified sha. Read as a contradiction, that costs a round trip and invites
somebody to go looking for a stale checkout that does not exist.

The third property is the one with real teeth: a red count is only diffable
against a baseline taken under THE SAME pin. Reporting "0 new" off the previous
pin's baseline would be the most reassuring possible way to be wrong, so when
the baseline does not match, the line must say the diff is unknown rather than
compute one.

Run: python3 tools/twatch_pin_verify_status_devtest.py
"""

import datetime
import io
import json
import os
import subprocess
import sys
import tempfile
from contextlib import redirect_stdout

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import twatch  # noqa: E402

fails = []
ran = []


def check(cond, what, detail=""):
    ran.append(what)
    print("  %-4s %-56s %s" % ("PASS" if cond else "FAIL", what, detail))
    if not cond:
        fails.append(what)


def ago(minutes):
    t = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=minutes)
    return t.strftime("%Y-%m-%dT%H:%M:%SZ")


class Fixture:
    """A scratch repo plus a synthetic tstate dir. Four commits, so `behind` is
    a real number read out of real git history rather than a stubbed one."""

    def __init__(self):
        self.d = tempfile.mkdtemp(prefix="pinverify-status-")
        self._git("init", "-q", "-b", "master", ".")
        self._git("config", "user.email", "t@example.invalid")
        self._git("config", "user.name", "t")
        with open(os.path.join(self.d, "f"), "w") as f:
            f.write("a\n")
        self._git("add", "f")
        self._git("commit", "-qm", "one")
        self.old = self._out("rev-parse", "HEAD")
        for i in (2, 3, 4):
            with open(os.path.join(self.d, "f"), "a") as f:
                f.write("%d\n" % i)
            self._git("commit", "-qam", "c%d" % i)
        self.head = self._out("rev-parse", "HEAD")
        self.tdir = os.path.join(self.d, "td")
        os.makedirs(self.tdir)

    def _git(self, *a):
        subprocess.run(("git",) + a, cwd=self.d, check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def _out(self, *a):
        return subprocess.run(("git",) + a, cwd=self.d, check=True,
                              capture_output=True, text=True).stdout.strip()

    def run(self, pin_verify, baseline=None, quiet=False, full_sha=None):
        st = {"host": "testbox",
              "last": {"sha": self.head, "verdict": "GREEN", "tier": "native",
                       "date": ago(4 * 24 * 60 if quiet else 5)},
              # DELIBERATELY a different sha from the pin's. The defect was a
              # reader taking last_full for the whole story, so a fixture where
              # the two agree could not tell a real pin line from one that
              # echoed the breadth line.
              "last_full": {"sha": full_sha or self.head, "verdict": "GREEN",
                            "tier": "full", "date": ago(90)},
              "jobs": {"a#00": "pass"}}
        if pin_verify is not None:
            st["pin_verify"] = pin_verify
        if baseline is not None:
            st["pin_baseline"] = baseline
        with open(os.path.join(self.tdir, "testbox.json"), "w") as f:
            json.dump(st, f)
        buf = io.StringIO()
        with redirect_stdout(buf):
            twatch.status(self.d, 60, tdir=self.tdir, ref="HEAD", fetch=False)
        return buf.getvalue()


def pinline(out):
    """The pin-verify line alone. Asserting against the WHOLE output would pass
    on text the breadth line already prints -- both name a sha and an age."""
    for ln in out.splitlines():
        if "pin verify" in ln:
            return ln
    return ""


def caveat(out):
    for ln in out.splitlines():
        if "AT THE PINNED TREE" in ln:
            return ln
    return ""


F = Fixture()
RED2 = ["tools-devtest#00", "lib-test#src:test/x.c"]

print("the pin's verdict is reported, and it is the PIN's, not last_full's")
out = F.run({"ver": "v366", "sha": F.old, "tier": "full", "verdict": "RED",
             "date": ago(19), "red": RED2})
ln = pinline(out)
check(bool(ln), "a completed pin verify produces a line at all",
      "this is the whole ticket: the data was there and --status did not say it")
check("v366" in ln, "...naming the pin version")
check(F.old[:12] in ln, "...and the sha THAT PIN sits at")
check(F.head[:12] not in ln,
      "...which is NOT last_full's sha",
      "a line that echoed the breadth line would pass every check above")
check("RED" in ln and "full" in ln, "...with the verdict and the tier")
check("19m" in ln, "...and an age in minutes, since a pin is held in minutes")
check("2 red" in ln, "...and how many jobs are red")

print("\na red at a frozen sha is not a contradiction with a green HEAD")
c = caveat(out)
check(bool(c), "the caveat line is printed when the pin is behind and red")
check("3 testable commit(s) behind" in c,
      "...counting the real distance from the pinned tree to HEAD",
      "read out of git history, not asserted from the fixture")
check("not a contradiction" in c,
      "...and saying plainly that green-at-HEAD does not refute it")

print("\nno diff is offered unless the baseline belongs to THIS pin")
ln = pinline(F.run({"ver": "v366", "sha": F.old, "tier": "full", "verdict": "RED",
                    "date": ago(19), "red": RED2},
                   baseline={"pin": "v365", "reds": RED2}))
check("no baseline recorded for v366" in ln,
      "a baseline from the PREVIOUS pin is refused, not used")
check(" new " not in ln,
      "...and specifically no new-count is printed from it",
      "'0 new' off the wrong pin is the most reassuring way to be wrong")
ln = pinline(F.run({"ver": "v366", "sha": F.old, "tier": "full", "verdict": "RED",
                    "date": ago(19), "red": RED2},
                   baseline={"pin": "v366", "reds": ["lib-test#src:test/x.c"]}))
check("1 new vs the v366 baseline" in ln,
      "a matching baseline yields the count that matters: what the pin ADDED")

print("\nthe quiet cases stay quiet")
check(pinline(F.run(None)) == "",
      "a host that has never verified a pin prints no pin line")
# The opposite of the breadth line's rule, deliberately. Quietness invalidates
# a HEAD verdict; it does not invalidate a verdict about a frozen sha, and the
# quiet host may be the only one that ever judged the current pin. Suppressing
# here would reproduce the defect in the quiet case.
q = F.run({"ver": "v366", "sha": F.old, "tier": "full", "verdict": "RED",
           "date": ago(19), "red": RED2}, quiet=True)
check("QUIET" in q, "(fixture check) the host really is quiet",
      "a 4-day-old last verdict against a 2-day threshold")
check(pinline(q) != "",
      "a QUIET host STILL reports its pin verdict",
      "a frozen sha's verdict does not go stale with the box")
out = F.run({"ver": "v367", "sha": F.old, "tier": "full", "verdict": "GREEN",
             "date": ago(3), "red": []})
ln = pinline(out)
check("GREEN" in ln and "red" not in ln,
      "a clean verify says GREEN and offers no red count")
check(caveat(out) == "",
      "...and no behind-caveat, which only exists to explain reds")

print("\nthe behind-caveat is about distance, not about being red")
out = F.run({"ver": "v366", "sha": F.head, "tier": "full", "verdict": "RED",
             "date": ago(19), "red": RED2})
check(caveat(out) == "",
      "a pin verified AT HEAD prints no caveat — there is no gap to explain")

print()
if fails:
    print("FAILED %d of %d check(s):" % (len(fails), len(ran)))
    for f in fails:
        print("  - " + f)
    sys.exit(1)
print("all %d pin-verify status guards green" % len(ran))
