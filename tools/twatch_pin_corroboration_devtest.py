#!/usr/bin/env python3
"""Devtest: a pin verify's red count is a HYPOTHESIS, and `--status` says so.

The count exists because `--status` learned on 2026-08-19 to report the pin's
verdict and not only HEAD's. Within the hour it printed:

    pin verify — v367 at d47acfee770c RED (full, 24m old), 20 red, 11 new vs the
    v367 baseline

Eleven new reds at a pin taken an hour earlier is a coordinator's documented
`make revert` trigger. All eleven passed in an ordinary full tier twenty-two
minutes later: uforth x5, sqlite-threads x2, c-conformance under qemu, demos,
tools-devtest and one nilpy job -- the load-shaped family, on a box that was
running a full tier at load 14 the same night. Nothing in compiler/** had moved.

The revert did not happen, because the peer holding the trigger chose to measure
instead of fire it, by hand, with six commands, at midnight. That is a good
outcome produced by no mechanism at all, and the next reader gets no such luck.

So the discriminator they ran runs here. Both keys are in the same file: a red
that PASSES in a full tier that ran AFTER the verify has been refuted by a
later, equally wide observation of the same job.

What the guards below actually protect, in order of how badly each would bite:

  * a red the later tier ALSO failed must never be called noise -- that is the
    real regression, and washing it out is worse than the defect being fixed;
  * "not yet corroborated" and "corroborated" must stay distinguishable, so a
    verify with no later tier says single-run rather than going silent, which
    reads as agreement;
  * only a FULL tier refutes, because `jobs` holds the newest status per job and
    a quick tier passing 200 of them says nothing about the 2500 it skipped;
  * and the subject must be the count the reader is about to act on -- the NEW
    reds when a baseline belongs to this pin, all of them when none does.

Run: python3 tools/twatch_pin_corroboration_devtest.py
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
    """Record one guard. `cond` may be a callable, and should be when its
    subject could raise.

    A raise inside a guard's subject used to end the FILE: no verdict for the
    claim that raised, none for any claim below it, and a traceback naming a
    line in twatch.py rather than the thing being asserted. Under a neuter --
    the one time a devtest is deliberately run against broken code -- that turns
    working guards into silence. Caught on 2026-08-20 when a neuter reddened two
    guards correctly, died on the third, and the harness read the run as clean.

    Second time this exact shape has bitten this campaign (the first was a
    KeyError in the exp_dur guards), so it is fixed in the harness rather than
    at the one call site.
    """
    ran.append(what)
    if callable(cond):
        try:
            cond = cond()
        except Exception as e:                                  # noqa: BLE001
            cond, detail = False, "RAISED %s: %s" % (type(e).__name__, e)
    print("  %-4s %-62s %s" % ("PASS" if cond else "FAIL", what, detail))
    if not cond:
        fails.append(what)


def ago(minutes):
    t = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=minutes)
    return t.strftime("%Y-%m-%dT%H:%M:%SZ")


NOW = None          # helper reads wall time; None lets secs_since use it


def state(red, later_jobs, pv_min=30, lf_min=8, ver="v367", baseline=None,
          lf_sha="2e8b284343a5", lf_tier="full"):
    """The two keys the corroboration reads, and nothing else."""
    st = {"jobs": dict(later_jobs),
          "last_full": {"sha": lf_sha, "tier": lf_tier, "verdict": "RED",
                        "date": ago(lf_min)}}
    if baseline is not None:
        st["pin_baseline"] = baseline
    pv = {"ver": ver, "sha": "d47acfee770c", "tier": "full", "verdict": "RED",
          "date": ago(pv_min), "red": list(red)}
    return pv, st


def co(*a, **kw):
    pv, st = state(*a, **kw)
    return twatch.pin_verify_corroboration(pv, st, NOW)


# ---------------------------------------------------------------- the incident
print("\nthe 2026-08-19 false alarm, reproduced from its own numbers")

INHERITED = ["lib-test#src:test/lib_mimic_xml_etree_elementtree.npy",
             "test-nilpy#src:test/test_cpyext_args_errors.npy",
             "test-nilpy#src:test/test_cpyext_containers.npy",
             "test-nilpy#src:test/test_cpyext_cython.npy",
             "test-nilpy#src:test/test_cpyext_errformat.npy",
             "test-nilpy#src:test/test_cpyext_hello.npy",
             "test-nilpy#src:test/test_cpyext_markupsafe.npy",
             "test-nilpy#src:test/test_nilpy_callable_to_str_param_fails.npy",
             "test-riscv32#src:test/test_cross_float.pas"]
NEW = ["test-nilpy#src:test/test_nilpy_pascal_unit_keeps_fpc_method_shadowing.npy",
       "test-uforth#corpus", "test-uforth#core", "test-uforth#coreplustest",
       "test-uforth#memorytest", "test-uforth#searchordertest",
       "test-c-conformance-riscv32#shard3/6",
       "test-sqlite-threads-aarch64#src:tools/run_sqlite_thread_test.sh",
       "test-sqlite-threads-arm32#src:tools/run_sqlite_thread_test.sh",
       "tools-devtest#00", "demos#00"]
BASE = {"pin": "v367", "reds": INHERITED}
# The real later tier: 2779 pass, 9 fail -- the nine being exactly the inherited
# set, which is why the eleven NEW ones are the whole question.
LATER = dict([(j, "fail") for j in INHERITED] + [(j, "pass") for j in NEW])

def incident():
    return co(INHERITED + NEW, LATER, pv_min=30, lf_min=8, baseline=BASE)


check(lambda: incident()["n"] == 11 and incident()["what"] == "new",
      "the subject is the 11 NEW reds, not all 20",
      "the inherited 9 were never the alarm")
check(lambda: len(incident()["refuted"]) == 11,
      "all 11 are refuted by the later full tier")
check(lambda: incident()["confirmed"] == [],
      "...and none of them is confirmed there",
      "which is what makes it a flake and not a regression")
check(lambda: incident()["sha"] == "2e8b284343a5"
      and 1300 < incident()["gap"] < 1340,
      "the refuting run is named, with the gap that makes it later")

# --------------------------------------------------- the case that must NOT wash out
print("\na red the later tier ALSO failed is a regression, never noise")
MIX = (["a#00", "b#00"], {"a#00": "fail", "b#00": "pass"})
check(lambda: co(*MIX)["confirmed"] == ["a#00"],
      "a job red in BOTH runs lands in `confirmed`")
check(lambda: co(*MIX)["refuted"] == ["b#00"],
      "...and only the one that passed later is refuted")
ALLBAD = (["a#00"], {"a#00": "fail"})
check(lambda: co(*ALLBAD)["confirmed"] == ["a#00"] and co(*ALLBAD)["refuted"] == [],
      "an all-confirmed set produces no refutation at all",
      "the count keeps its full weight")

print("\nsilence in the later tier is not agreement")
check(lambda: co(["a#00", "b#00"], {"b#00": "pass"})["refuted"] == ["b#00"]
      and co(["a#00", "b#00"], {"b#00": "pass"})["confirmed"] == [],
      "a job ABSENT from the later map is in neither list")
check(lambda: co(["a#00"], {"a#00": "skip"})["refuted"] == []
      and co(["a#00"], {"a#00": "skip"})["confirmed"] == [],
      "a SKIPPED job refutes nothing — it was not run")

# --------------------------------------------------------- only a later run counts
print("\nonly a run that came AFTER the verify can refute it")
OLDER = (["a#00"], {"a#00": "pass"})
check(lambda: co(*OLDER, pv_min=8, lf_min=30)["sha"] is None,
      "a full tier OLDER than the verify corroborates nothing")
check(lambda: co(*OLDER, pv_min=8, lf_min=30)["n"] == 1
      and co(*OLDER, pv_min=8, lf_min=30)["what"] == "",
      "...but the subject is still reported, so the caller can say `single run`",
      "absence of a check is not absence of a count")
check(lambda: co(*OLDER, pv_min=20, lf_min=20)["sha"] is None,
      "the same timestamp is not LATER — strictly newer is required")
check(lambda: co(*OLDER, pv_min=30, lf_min=8)["sha"] is not None,
      "a strictly later full tier does corroborate")

print("\nthe subject is whatever count the reader is about to act on")
MINE = {"pin": "v367", "reds": ["a#00"]}
THEIRS = {"pin": "v366", "reds": ["a#00"]}
check(lambda: co(["a#00", "b#00"], {}, baseline=MINE)["n"] == 1
      and co(["a#00", "b#00"], {}, baseline=MINE)["what"] == "new",
      "a baseline belonging to THIS pin narrows the subject to the new reds")
check(lambda: co(["a#00", "b#00"], {}, baseline=THEIRS)["n"] == 2
      and co(["a#00", "b#00"], {}, baseline=THEIRS)["what"] == "",
      "a baseline from ANOTHER pin is refused; all reds are the subject",
      "same rule the printed count already obeys")
check(lambda: co(["a#00", "b#00"], {})["n"] == 2
      and co(["a#00", "b#00"], {})["what"] == "",
      "no baseline at all — all reds are the subject")

print("\nan unreadable date degrades to `cannot corroborate`, not to a crash")
def degraded(mutate):
    pv, st = state(["a#00"], {"a#00": "pass"})
    mutate(pv, st)
    return twatch.pin_verify_corroboration(pv, st, NOW)


def setdate(pv, st):
    pv["date"] = "not-a-date"


def nofull(pv, st):
    st["last_full"] = {}


check(lambda: degraded(setdate)["sha"] is None,
      "an unparseable verify date yields no corroboration")
check(lambda: degraded(nofull)["sha"] is None,
      "a host with no last_full at all yields no corroboration")


# ------------------------------------------------------------------ the printed line
class Fixture:
    """A scratch repo plus a synthetic tstate dir — the line, not the helper."""

    def __init__(self):
        self.d = tempfile.mkdtemp(prefix="pincorrob-")
        self._git("init", "-q", "-b", "master", ".")
        self._git("config", "user.email", "t@example.invalid")
        self._git("config", "user.name", "t")
        with open(os.path.join(self.d, "f"), "w") as f:
            f.write("a\n")
        self._git("add", "f")
        self._git("commit", "-qm", "one")
        for i in (2, 3):
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

    def run(self, red, later_jobs, pv_min=30, lf_min=8, baseline=None,
            verdict="RED"):
        st = {"host": "testbox",
              "last": {"sha": self.head, "verdict": "GREEN", "tier": "native",
                       "date": ago(5)},
              # A sha of its own: a line that echoed the breadth line instead of
              # naming the refuting run would pass a fixture where they agree.
              "last_full": {"sha": "2e8b284343a5", "verdict": "RED",
                            "tier": "full", "date": ago(lf_min)},
              "jobs": dict(later_jobs),
              "pin_verify": {"ver": "v367", "sha": self.head, "tier": "full",
                             "verdict": verdict, "date": ago(pv_min),
                             "red": list(red)}}
        if baseline is not None:
            st["pin_baseline"] = baseline
        with open(os.path.join(self.tdir, "testbox.json"), "w") as f:
            json.dump(st, f)
        buf = io.StringIO()
        with redirect_stdout(buf):
            twatch.status(self.d, 60, tdir=self.tdir, ref="HEAD", fetch=False)
        return buf.getvalue()


def corrob(out):
    """The corroboration line alone. Matching the whole output would pass on
    the pin line above it, which already names a sha, an age and a red count."""
    for ln in out.splitlines():
        if ("CORROBORATED" in ln or "corroborated" in ln
                or "reported on none" in ln):
            return ln
    return ""


print("\nthe line a reader with a revert trigger actually sees")
F = Fixture()
out = F.run(INHERITED + NEW, LATER, baseline=BASE)
ln = corrob(out)
check("NOT CORROBORATED" in ln,
      "an all-refuted count is labelled NOT CORROBORATED")
check("11 of those 11 new reds" in ln,
      "...naming both counts, so the reader sees it is the whole set",
      ln.strip()[:60])
check("2e8b284343a5" in ln,
      "...and the run that refutes it, by sha")
check("revert" in ln.lower(),
      "...and says not to revert on the count alone",
      "the trigger this fires under is a documented revert")
check(F.head[:12] not in ln,
      "the sha named is the LATER tier's, never the pin's",
      "an echo of the pin line would refute nothing")

out = F.run(["a#00", "b#00"], {"a#00": "fail", "b#00": "pass"})
ln = corrob(out)
check("corroborated in part" in ln and "1 of 2" in ln,
      "a mixed set is reported as corroborated in part, with the real count",
      ln.strip()[:60])
check("the other 1 pass there" in ln,
      "...and the refuted remainder is still named as noise")

out = F.run(["a#00"], {"a#00": "fail"})
check("the other" not in corrob(out),
      "an all-confirmed set claims no noise at all")

out = F.run(["a#00", "b#00"], {"a#00": "pass"}, pv_min=8, lf_min=30)
ln = corrob(out)
check("SINGLE RUN" in ln and "no full tier has run since" in ln,
      "with no later tier the line says single-run, rather than going silent",
      "silence would read as agreement")
check("those 2 reds rest on one pass" in ln,
      "...and still names the count that rests on it")

out = F.run([], {}, verdict="GREEN")
check(corrob(out) == "",
      "a GREEN verify with no reds prints no corroboration line",
      "there is no count to weigh")

print()
if fails:
    print("FAILED %d of %d guard(s):" % (len(fails), len(ran)))
    for f in fails:
        print("  - " + f)
    sys.exit(1)
print("all %d pin-verify corroboration guards green" % len(ran))
