#!/usr/bin/env python3
"""Devtest: a red job records WHY, and the why is never the wrong run's.

bug-t-a-red-job-records-no-reason. tstate stored a failed job as the bare string
`fail` -- and `tools-devtest#00` alone runs 46 guard scripts, so "fail" named one
of 46 without saying which. Triaging a cascade meant re-running the job, and a
re-run at a later sha answers a different question than the one that was asked:
on 2026-08-19 the reason a cascade job was red became unrecoverable that way.

Two halves, guarded here together because each is useless without the other:

  * testmgr.job_reason() -- what to record. The log TAIL, capped, /tmp scrubbed,
    trailing make-noise dropped.
  * twatch.update_job_reasons() -- what to KEEP. The rule with teeth is that a
    run which produced a job either sets its reason or CLEARS it; a previous
    run's explanation left attached to this run's failure is a true sentence
    about the wrong subject, which is the defect class this ticket belongs to.
"""

import os
import sys
import tempfile
import types

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import testmgr  # noqa: E402
import twatch  # noqa: E402
from devtest_report import fail_detail  # noqa: E402

fails = []


def check(cond, what, detail=""):
    print("  %-4s %-54s %s" % ("PASS" if cond else "FAIL", what, detail))
    if not cond:
        fails.append(what)


_TMP = tempfile.mkdtemp(prefix="jobreason-")
_N = [0]


def reason(text):
    """job_reason() over a log holding `text`."""
    _N[0] += 1
    p = os.path.join(_TMP, "j%d.log" % _N[0])
    with open(p, "w") as f:
        f.write(text)
    return testmgr.job_reason(types.SimpleNamespace(logpath=p))


MAKE_ERR = "make: *** [Makefile:12: test-core#809] Error 1\n"

print("the reason is what the job printed, not that it failed")
r = reason("running check\nFAIL: expected 3 got 4\n" + MAKE_ERR)
check("expected 3 got 4" in r, "the substantive line survives")
check("Error 1" not in r, "and the make line is DROPPED",
      "status+name already say it; keeping it makes every reason identical")

print("\ntstate is committed to git, so the reason must be git-stable")
r = reason("wrote /tmp/testmgr-scratch-99123/a.bin\nboom\n" + MAKE_ERR)
check("$TMP" in r and "99123" not in r, "the pid-keyed scratch path is scrubbed",
      "else every run dirties tstate with nothing changed")
r = reason("\n".join("padding line %d that goes on a while" % i
                     for i in range(60)) + "\n" + MAKE_ERR)
check(len(r) <= testmgr.REASON_MAX, "and the whole thing is capped at %d"
      % testmgr.REASON_MAX, "%d chars" % len(r))

print("\nnoise is dropped from the END only")
r = reason("make: *** [sub] Error 1\nretried and got further\nreal failure\n" + MAKE_ERR)
check("[sub] Error 1" in r, "a mid-log sub-make failure is kept",
      "it is part of the story; dropping it rewrites the story")

print("\nan unrecoverable reason reads as unrecoverable, never as 'no reason'")
check(reason(MAKE_ERR) == "", "a log with nothing but noise yields ''")
check(testmgr.job_reason(types.SimpleNamespace(logpath=None)) == "",
      "no log path yields '' rather than raising")
check(testmgr.job_reason(types.SimpleNamespace(logpath=_TMP + "/gone.log")) == "",
      "a log the OS already reaped yields '' too")

# ---------------------------------------------------------------- the twatch half


def rep(*jobs):
    return {"jobs": [dict({"name": n, "sel": n, "status": s, "reason": w})
                     for n, s, w in jobs]}


print("\na red job's reason is stored beside its status, not inside it")
st = {}
twatch.update_job_reasons(st, rep(("a#00", "fail", "assert x == 1")),
                          {"a#00": "fail"})
check(st["job_reason"] == {"a#00": "assert x == 1"}, "the sibling map carries it")
check("jobs" not in st, "and st['jobs'] is untouched",
      "several readers take those values as bare strings")

print("\na job that goes green loses its reason")
twatch.update_job_reasons(st, rep(("a#00", "pass", "")), {"a#00": "pass"})
check("job_reason" not in st, "a stale why on a green job is worse than none")

print("\nTHE RULE WITH TEETH: a run that produced the job clears a stale reason")
st = {"job_reason": {"a#00": "assert x == 1"}}      # from an earlier run
# Still red -- but this run recovered no log, so it has no reason of its own.
twatch.update_job_reasons(st, rep(("a#00", "fail", "")), {"a#00": "fail"})
check("a#00" not in (st.get("job_reason") or {}),
      "the previous run's explanation is DELETED, not carried",
      "keeping it attributes an old cause to a new failure")

print("\na red this run did NOT re-run keeps the reason that matches its status")
st = {"job_reason": {"b#00": "segfault in Copy()"}}
twatch.update_job_reasons(st, rep(("a#00", "pass", "")),
                          {"a#00": "pass", "b#00": "fail"})
check(st["job_reason"] == {"b#00": "segfault in Copy()"},
      "because the status it keeps is that same run's")

print("\na CARRIED red keeps its reason — the resume is sha-guarded")
# apply_resume() passes the earlier report's job dicts through verbatim, and
# load_resume() refuses a partial whose compiler sha256 does not match, so a
# carried result IS attributable to the binary this run tested. Its reason came
# from the same run as its status, which is the only rule this map enforces.
st = {}
twatch.update_job_reasons(st, rep(("c#00", "fail", "carried: diff mismatch")),
                          {"c#00": "fail"})
check(st["job_reason"] == {"c#00": "carried: diff mismatch"},
      "so it is stored like any other")
# ...but a partial written by an OLDER testmgr has no `reason` key at all.
st = {"job_reason": {"c#00": "from some earlier run"}}
twatch.update_job_reasons(st, {"jobs": [{"name": "c#00", "sel": "c#00",
                                         "status": "fail"}]}, {"c#00": "fail"})
check("job_reason" not in st, "and a pre-feature carried dict clears, not keeps",
      "unattributable beats plausible; it self-heals on the next real run")

print("\nthe map can never outlive the map it annotates")
st = {"job_reason": {"gone#00": "why"}}
twatch.update_job_reasons(st, rep(), {})           # pruned from st["jobs"]
check("job_reason" not in st, "a key the orphan prune dropped loses its reason")

print("\na cap that trims says what it dropped")
many = {"j#%03d" % i: "fail" for i in range(twatch.JOB_REASON_CAP + 5)}
st = {}
twatch.update_job_reasons(
    st, rep(*[(k, "fail", "why %s" % k) for k in many]), many)
check(len(st["job_reason"]) == twatch.JOB_REASON_CAP,
      "the map is bounded at %d" % twatch.JOB_REASON_CAP)
check(sorted(st["job_reason"]) == sorted(many)[:twatch.JOB_REASON_CAP],
      "and which survive is by name, so it is reproducible",
      "dict order is not an answer")

print("\nevery red in the report names its reason, not only the first")
# The `first failure:` block dumps ONE log. A 13-job cascade left the other
# twelve as bare names in NEW-RED / STILL-RED, which is the markdown half of the
# same defect: the document a human reads days later said WHICH job and not WHY.
class _Clone:
    path = _TMP


jobs = [{"name": n, "sel": n, "status": "fail", "src": "test/%s.pas" % n,
         "reason": "assert failed in %s" % n} for n in ("d#00", "e#00")]
rel = twatch.write_report_md(
    _Clone(), "plexus", "a" * 40, "b" * 40,
    {"tier": "full", "wall": 1.0, "scale": 1.0, "verdict": "RED",
     "jobs": jobs, "compiler_sha256": "abc"},
    ["d#00"], [], ["e#00"], {})
body = open(os.path.join(_TMP, rel)).read()
check("assert failed in d#00" in body, "the NEW-RED entry carries its reason")
check("assert failed in e#00" in body, "and so does the STILL-RED one",
      "the one the first-failure dump never reaches")

print()
if fails:
    print("FAILED %d check(s):" % len(fails))
    for f in fails:
        print("  - " + f)
    sys.exit(1)
print("job-reason guards green")
