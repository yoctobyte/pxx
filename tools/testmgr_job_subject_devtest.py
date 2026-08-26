#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a red must arrive carrying its subject.

The owner's rule is that float accuracy is LOW PRIO by definition, and
`devdocs/progress/float/` implements it by hiding those tickets from
`ready`/`next`. That governs TICKETS, not REDS — and a red is worked at the
priority of BEING RED, because nobody triaging a red first asks whether its
topic was de-ranked. So a de-ranked subject re-enters the queue at the top
through a door the `prio:` field cannot reach. 23 recorded red/fixed events on
float-named jobs say the door is real.

The fix labels rather than de-gates: the red still fires at full strength, it
just arrives saying what it is about, in the line the triager is already
reading. A wrong label costs a wrong label; a wrongly de-gated test costs a
silent hole, and those are not comparable.

Two properties, and the second is the one with teeth:

  * a subject is DECLARED by the test, never inferred. Inference from a filename
    would label `test_nilpy_math_domain_errors.npy` as float-accuracy when its
    subject is NaN/Inf handling — the exact test the escape rule says must stay
    full strength. Same mistake as exempting a job because its recipe invokes
    xvfb-run: reading the surface gets the motivating case backwards.
  * an undeclared job reports "", and "" means "the test did not say" — never
    "not float". A default that asserts something is how a blank becomes a
    claim.

Run: tools/testmgr_job_subject_devtest.py   (exit 0 = pass)
"""
import importlib.util
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tm", os.path.join(HERE, "testmgr.py"))
tm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tm)

FAILS = []


def check(name, cond, detail=""):
    if cond:
        print("  ok   %s" % name)
    else:
        print("  RED  %s" % name)
        FAILS.append("%s\n      %s" % (name, detail))


class FakeJob(object):
    def __init__(self, lines, status="fail"):
        self.lines = lines
        self.status = status
        self.sel = self.name = "fake#0"


def main():
    print("testmgr: a red must arrive carrying its subject")
    d = tempfile.mkdtemp(prefix="subject-devtest-")
    old_repo = tm.REPO
    tm.REPO = d

    def write(rel, text):
        full = os.path.join(d, rel)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        open(full, "w").write(text)
        return rel

    try:
        # Every comment syntax a declaring test might use.
        npy = write("test/a.npy", "# PXX-SUBJECT: float-accuracy\nprint(1.0)\n")
        pas = write("test/b.pas", "{ PXX-SUBJECT: float-accuracy }\nbegin end.\n")
        c = write("test/c.c", "/* PXX-SUBJECT: float-accuracy */\nint main(){}\n")
        plain = write("test/d.pas", "{ an ordinary test }\nbegin end.\n")
        # A filename that screams float, with a subject that is not.
        trap = write("test/test_nilpy_math_float_domain_errors.npy",
                     "# NaN and -Inf handling, diffed against CPython\n"
                     "import math\n")

        for rel, kind in ((npy, ".npy #"), (pas, ".pas {}"), (c, ".c /* */")):
            j = FakeJob(["./compiler/pascal26 %s /tmp/x" % rel, "/tmp/x"])
            check("reads a declaration in %s" % kind,
                  tm.job_subject(j) == "float-accuracy",
                  "got %r" % tm.job_subject(j))

        j = FakeJob(["./compiler/pascal26 %s /tmp/x" % plain, "/tmp/x"])
        check("an undeclared test reports \"\"", tm.job_subject(j) == "",
              "got %r — a default that asserts something turns a blank into a "
              "claim" % tm.job_subject(j))

        j = FakeJob(["./compiler/pascal26 %s /tmp/x" % trap, "/tmp/x"])
        check("a float-SOUNDING filename is NOT enough to label it",
              tm.job_subject(j) == "",
              "inference would have de-ranked a NaN/Inf test, which the escape "
              "rule says must stay full strength; got %r" % tm.job_subject(j))

        # A job naming several sources: the first declaration wins, and a
        # non-declaring source must not mask a declaring one.
        j = FakeJob(["./compiler/pascal26 %s /tmp/x" % plain,
                     "./compiler/pascal26 %s /tmp/y" % npy, "/tmp/x"])
        check("a declaration is found on any source the job names",
              tm.job_subject(j) == "float-accuracy",
              "got %r" % tm.job_subject(j))

        # Missing/unreadable file must not raise — a red is being reported and
        # this runs on the failure path.
        j = FakeJob(["./compiler/pascal26 test/gone.pas /tmp/x"])
        try:
            got = tm.job_subject(j)
            check("an unreadable source yields \"\" rather than raising",
                  got == "", "got %r" % got)
        except Exception as e:  # noqa: BLE001
            check("an unreadable source yields \"\" rather than raising",
                  False, "raised %r on the red-reporting path" % (e,))

        # A partial stand-in with no `lines` at all. report_job() runs while
        # REPORTING a failure, so raising here would turn one red job into no
        # report — strictly worse than the labelling it was added to provide.
        # Caught by report_exp_dur_devtest.py, which builds exactly such a job.
        import types
        try:
            got = tm.job_subject(types.SimpleNamespace(status="fail"))
            check("a job with no `lines` yields \"\" rather than raising",
                  got == "", "got %r" % got)
        except Exception as e:  # noqa: BLE001
            check("a job with no `lines` yields \"\" rather than raising",
                  False, "raised %r while reporting a red" % (e,))

        # The note is the load-bearing half: a bare tag still leaves the reader
        # needing to know the owner's rule.
        note = tm.SUBJECT_NOTE.get("float-accuracy", "")
        check("the triage note states the rule", "LOW PRIO" in note, note)
        check("...and states the escape rule in the same breath",
              "NaN" in note and "full strength" in note,
              "without this the label reads as 'ignore float reds':\n%s" % note)

        # twatch renders it independently (different clone, different sha, so
        # it cannot import testmgr) — the tables must not drift apart.
        tws = importlib.util.spec_from_file_location(
            "tw", os.path.join(HERE, "twatch.py"))
        tw = importlib.util.module_from_spec(tws)
        tws.loader.exec_module(tw)
        check("twatch carries a note for every subject testmgr defines",
              set(tm.SUBJECT_NOTE) <= set(tw.SUBJECT_NOTES),
              "missing in twatch: %s"
              % (set(tm.SUBJECT_NOTE) - set(tw.SUBJECT_NOTES)))
        check("twatch's note also carries the escape rule",
              "full strength" in tw.SUBJECT_NOTES.get("float-accuracy", ""),
              tw.SUBJECT_NOTES.get("float-accuracy", ""))
    finally:
        tm.REPO = old_repo

    if FAILS:
        print("\ntestmgr_job_subject_devtest: %d RED" % len(FAILS))
        for f in FAILS:
            print("  - %s" % f)
        return 1
    print("testmgr_job_subject_devtest: all green")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:  # noqa: BLE001
        print(fail_detail(e))
        sys.exit(1)
