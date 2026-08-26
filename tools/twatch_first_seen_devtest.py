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


class _FakeClone:
    """Answers `git show --name-only` from a dict, so the filter is tested
    without a repo."""
    path = "/nonexistent"

    def __init__(self, files_by_sha):
        self.files = files_by_sha


def _patch_sh(clone):
    orig = tw.sh

    def fake(cmd, cwd=None, check=True):
        assert cmd[:3] == ["git", "show", "--name-only"], cmd
        return "\n".join(clone.files.get(cmd[-1], []))
    tw.sh = fake
    return orig


def t_a_pin_built_range_keeps_lib_and_test_commits():
    """THE correction that matters, and the direction that is dangerous.

    The first cut of this replaced the range with pin moves only -- 137 commits
    down to 2 -- which silently discarded 36 lib/ and test/ commits the job
    builds from directly. `make pin` freezes compiler/builtin/** and
    DELIBERATELY leaves lib/rtl live ("track B's own editable lane"), so a
    pin-built job absolutely can see them. A too-wide range costs bisect steps;
    a too-narrow one excludes the culprit, which is the failure that matters.
    """
    clone = _FakeClone({
        "pin" + "0" * 37: ["stable_linux_amd64/default/pin.log"],
        "lib" + "0" * 37: ["lib/rtl/sysutils.pas"],
        "tst" + "0" * 37: ["test/foo.npy"],
        "cmp" + "0" * 37: ["compiler/parser.inc"],
        "doc" + "0" * 37: ["devdocs/progress/BOARD.md"],
        "mix" + "0" * 37: ["compiler/parser.inc", "lib/rtl/x.pas"],
        "non" + "0" * 37: [],
    })
    orig = _patch_sh(clone)
    try:
        keep = tw.pin_observable(clone, list(clone.files))
    finally:
        tw.sh = orig
    assert "lib" + "0" * 37 in keep, "a lib/ commit IS observable by a pin build"
    assert "tst" + "0" * 37 in keep, "a test/ commit IS observable"
    assert "pin" + "0" * 37 in keep, "a pin move IS observable"
    assert "mix" + "0" * 37 in keep, "compiler/ + lib/ is still observable"
    assert "non" + "0" * 37 in keep, "unknown files must never narrow the range"
    assert "cmp" + "0" * 37 not in keep, "a compiler-only commit is not observable"
    assert "doc" + "0" * 37 not in keep, "a docs-only commit is not observable"
    return "keeps lib/test/pin/mixed/unknown, drops compiler-only and docs-only"


def t_a_pin_built_note_counts_observable_commits():
    note = tw.range_note({"bad": "a" * 40, "good": "b" * 40,
                          "range": ["c" * 40, "d" * 40], "pin_axis": True})
    assert "observable commit(s)" in note, (
        "a pin-built range must say what it counted, and why compiler/ is gone")
    assert "pin move(s)" not in note, (
        "counting pin moves alone was the wrong cut; the note must not "
        "re-describe the corrected range in the discarded units")
    return "pin-built range reports 2 observable commits"


def t_nothing_observable_changed_is_a_real_verdict():
    """The answer the system could not previously express. Every red on a
    pin-built job implicitly asserted 'something it builds with changed'; for
    an interval with no pin move and no lib/test commit that is simply false."""
    note = tw.range_note({"bad": "a" * 40, "good": "b" * 40,
                          "range": [], "pin_axis": True})
    low = note.lower()
    assert "nothing this job can observe changed" in low, (
        "an empty pin-built range must SAY what did not change -- that is "
        "information, not an absence of it")
    assert "no idle bisect" in low
    return "empty pin-built range reads as a verdict, not a gap"


def t_a_first_seen_note_says_first_ever_run():
    note = tw.range_note({"bad": "a" * 40, "range": [], "first_seen": True})
    low = note.lower()
    assert "first-ever run" in low, "a first-seen red must say so"
    assert "no idle bisect" in low
    return "first-seen red reads as a finding, not a regression"


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
               t_a_pin_built_range_keeps_lib_and_test_commits,
               t_a_pin_built_note_counts_observable_commits,
               t_nothing_observable_changed_is_a_real_verdict,
               t_a_first_seen_note_says_first_ever_run,
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
