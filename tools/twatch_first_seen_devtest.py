#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a job's FIRST execution must not inherit a range it never earned.

`diff_jobs()` reads a job's previous status as `prev_jobs.get(n, "pass")`. One
default, two questions:

  * for the VERDICT it is right — a job that is red the first time it ever runs
    must be reported red, not absorbed into silence;
  * for the RANGE it is a fabrication — the job has no earlier passing sha, so
    no interval contains its cause, and every commit a range could name is
    equally innocent.

That bites precisely when a rung is ENROLLED, which is the moment never-seen
jobs come into existence. test-fgl had spent its whole life printing
`SKIP (no fpcsrc)` from inside test-core; test-fpjson was in no tier at all.
Enrolling both (task-t-enrol-the-fgl-corpus-rung) would have filed their first
execution as a NEW-RED against a green history they never had.

It is the fourth face of one defect — the range is computed from what CHANGED
without asking whether the job could SEE it — and the worst of the four,
because a bisect over such a range does not fail. It terminates, prints a sha,
and is indistinguishable downstream from a correct answer.

Run: tools/twatch_first_seen_devtest.py   (exit 0 = pass)
"""
import importlib.util
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tw", os.path.join(HERE, "twatch.py"))
tw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tw)


def rep(*pairs):
    return {"jobs": [{"sel": n, "name": n, "status": s} for n, s in pairs]}


def t_a_never_seen_job_is_flagged_first_seen():
    _now, _nr, _fx, _sr, first = tw.diff_jobs({"old#00": "pass"},
                                              rep(("old#00", "pass"),
                                                  ("new#00", "fail")))
    assert "new#00" in first, "a job absent from prev_jobs must be first_seen"
    assert "old#00" not in first, "a known job must not be first_seen"
    return "first_seen names exactly the jobs with no history"


def t_a_first_seen_red_is_still_reported_red():
    """The half that must NOT change. Suppressing it would hide a real finding
    behind the fix for a wrong range."""
    _now, new_red, _fx, _sr, first = tw.diff_jobs({"old#00": "pass"},
                                                  rep(("old#00", "pass"),
                                                      ("new#00", "fail")))
    assert "new#00" in new_red, (
        "a job that is red on its first run must still be a NEW-RED — the "
        "range is what it cannot have, not the report")
    assert "new#00" in first
    return "red on arrival is reported; only its range is withheld"


def t_a_known_job_going_red_is_not_first_seen():
    _now, new_red, _fx, _sr, first = tw.diff_jobs({"j#00": "pass"},
                                                  rep(("j#00", "fail")))
    assert new_red == ["j#00"], "an ordinary regression must be unaffected"
    assert first == [], "nothing is first_seen when everything has history"
    return "ordinary regressions keep their range"


def t_a_first_seen_pass_is_not_a_fixed():
    """`fixed` uses the same default from the other side: a job appearing GREEN
    for the first time is not a recovery, and must not be published as one."""
    _now, _nr, fixed, _sr, first = tw.diff_jobs({}, rep(("new#00", "pass")))
    assert fixed == [], "a first-ever PASS is not a FIXED"
    assert first == ["new#00"]
    return "a first-ever pass does not read as a recovery"


def t_range_note_says_no_bisect_for_an_empty_range():
    """The words the fix routes first-seen jobs to. They already existed; the
    defect was that nothing reached them."""
    note = tw.range_note({"bad": "a" * 40, "range": []})
    low = note.lower()
    assert "unknown" in low, "an empty range must not be described as a range"
    assert "no idle bisect" in low, (
        "an empty range must state that no bisect will happen — a promise "
        "nothing can keep is how a red sits for days waiting")
    return "empty range reads as unknown + no bisect"


def t_a_populated_range_still_promises_the_bisect():
    note = tw.range_note({"bad": "a" * 40, "good": "b" * 40,
                          "range": ["c" * 40, "d" * 40]})
    assert "2 commit(s)" in note, "a real range must still report its size"
    assert "no idle bisect" not in note.lower()
    return "a real range is unchanged"


def main():
    rc = 0
    for fn in (t_a_never_seen_job_is_flagged_first_seen,
               t_a_first_seen_red_is_still_reported_red,
               t_a_known_job_going_red_is_not_first_seen,
               t_a_first_seen_pass_is_not_a_fixed,
               t_range_note_says_no_bisect_for_an_empty_range,
               t_a_populated_range_still_promises_the_bisect):
        try:
            print("  ok   %s — %s" % (fn.__name__, fn()))
        except Exception as e:              # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s"
                  % (fn.__name__, type(e).__name__, fail_detail(e)))
    print("first-seen OK" if rc == 0 else "first-seen BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
