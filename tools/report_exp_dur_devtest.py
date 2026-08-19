#!/usr/bin/env python3
"""Devtest: the report carries the BASELINE, not just the duration.

bug-t-makefile-inner-timeouts-are-invisible-to-testmgrs-contention-logic.

testmgr has recorded a per-job `dur` since forever, and testmgr alone knows what
that number should have been -- `Job.exp_dur`, the learned EWMA it sets at
dispatch and already prints to the console ("SLOW (expected 40.0s)"). That note
never left the terminal. Every consumer that OUTLIVES the run -- twatch, a
cascade ticket, a human reading the JSON tomorrow -- got `"dur": 361.0` with
nothing beside it, and a bare number cannot distinguish a machine under load
from a job that simply takes six minutes.

The specific failure that motivates it: an inner `timeout` inside a Makefile
recipe (the uforth corpus rows) exits the recipe ZERO and reports its truncated
output as a differential DIFF. Nothing in the status says "slow". The cost is
nevertheless sitting in `dur`, and with a baseline next to it the run is legible
as contention anyway.

So the two things guarded here are: the baseline is present, and the ABSENCE of
a baseline is stated as absence rather than as zero.
"""

import json
import os
import sys
import types

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import testmgr  # noqa: E402

fails = []
ran = []


def check(cond, what, detail=""):
    ran.append(what)
    print("  %-4s %-58s %s" % ("PASS" if cond else "FAIL", what, detail))
    if not cond:
        fails.append(what)


def job(**kw):
    """A Job-shaped stub carrying only what report_job() reads."""
    d = dict(name="test-uforth#00", cls="slow", src="test/uforth",
             sel="test-uforth#00", pin_built=False, advisory=False,
             status="pass", flaky=False, attempts=1,
             t0=100.0, t1=461.0,            # 361s wall
             exp_dur=40.0, peak_rss=1024, cpu_sec=12.25,
             logpath="/tmp/x.log")
    d.update(kw)
    return types.SimpleNamespace(**d)


# Read the field through .get() rather than [] throughout. If the key is simply
# ABSENT -- the state before this fix, and the state a bad merge would restore --
# a bare subscript raises on the first check and the run ends in a stack trace
# with the remaining guards unreported. A named FAIL says what broke; a
# KeyError says only where.
MISSING = object()


def expd(r):
    return r.get("exp_dur", MISSING)


print("the measurement and the thing it should be measured against")
r = testmgr.report_job(job())
check(r["dur"] == 361.0, "dur is the wall time, unchanged by the extraction")
check("exp_dur" in r, "the report HAS an exp_dur key at all",
      "absent is the pre-fix state, and it must fail by name, not by KeyError")
check(expd(r) == 40.0, "exp_dur rides along — the baseline is IN the report")
check(expd(r) is not MISSING and r["dur"] / expd(r) > 9,
      "...so a consumer can see 9x without its own history",
      "the whole point: contention is legible from the JSON alone")

# A stub that returned `dur` for both would pass "exp_dur is present" and every
# ratio check that only asserts the field exists. Give the two fields different
# values and assert the LEARNED one, or the guard is satisfied by a report that
# says every job ran exactly as long as expected.
check(expd(testmgr.report_job(job(t1=140.0, exp_dur=40.0))) == 40.0,
      "exp_dur is the LEARNED value, never re-derived from this run's dur")

print("\nno baseline yet is said as ABSENCE, never as zero")
r = testmgr.report_job(job(exp_dur=None))
check(expd(r) is None, "an unlearned job reports None")
check(expd(json.loads(json.dumps(r))) is None,
      "and it survives the JSON round-trip as null, not as missing")
# The reason the distinction has teeth: a consumer dividing by it.  With 0.0 the
# division raises or, worse, the consumer guards with `if exp_dur:` and silently
# treats a never-measured job as unremarkable.  None forces the branch.
check(expd(testmgr.report_job(job(exp_dur=0.0))) is None,
      "a stored 0.0 is normalised to None too — same claim, same answer")

print("\nrounding is applied to the baseline as it is to the duration")
r = testmgr.report_job(job(exp_dur=40.049999, t0=0.0, t1=1.2345))
check(expd(r) == 40.0, "exp_dur is rounded to 0.1s")
check(r["dur"] == 1.2, "dur is rounded to 0.1s")

print("\nthe extraction from main() dropped nothing")
r = testmgr.report_job(job(status="fail", flaky=True, attempts=3,
                           advisory=True, pin_built=True))
expect = {"name", "cls", "src", "sel", "pin_built", "advisory", "status",
          "flaky", "attempts", "dur", "exp_dur", "mem", "cpu", "reason", "log"}
check(set(r) == expect,
      "the key set is exactly the documented one",
      "missing: %s / extra: %s" % (sorted(expect - set(r)), sorted(set(r) - expect)))
check(r["pin_built"] is True and r["advisory"] is True and r["flaky"] is True
      and r["attempts"] == 3 and r["status"] == "fail",
      "every field main() used to build inline still passes through")
check(testmgr.report_job(job(sel=None))["sel"] == "test-uforth#00",
      "sel still falls back to name when the job has none")
check(testmgr.report_job(job(status="pass"))["reason"] == "",
      "a passing job still records no reason")

print()
if fails:
    print("FAILED %d of %d check(s):" % (len(fails), len(ran)))
    for f in fails:
        print("  - " + f)
    sys.exit(1)
print("all %d report-baseline guards green" % len(ran))
