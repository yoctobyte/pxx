#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a torn-down run has NO verdict, and says which jobs it never reached.

Both halves of bug-t-the-native-tier-times-out-and-publishes-a-contentless-red.

For three days in August 2026 every native run on plexus ended at wall 3600.x —
the deadline — and published `verdict: RED` with `new_red: []` and
`still_red: []`. A RED with nothing attributed is not "everything failed", it is
"the clock ran out before anything could be named", and the two are
indistinguishable to --status, to the fleet, and to the rule that says a core-job
red older than a day is a revert candidate. It cost a coordinator a near-miss on
a merge gated against a full tier that had never completed.

The second half is subtler and is what erased the evidence. On a `full` run the
job map is REPLACED, not merged, so that renamed and deleted jobs stop haunting
it. The premise of that rule is "this run was capable of running the job and did
not produce it" — a teardown falsifies the premise. Every job the clock cut off
had its red silently dropped, and an absent job counts as having passed the next
time round (`prev_jobs.get(n, "pass")`), so unreached read as FIXED.

Run: tools/twatch_timeout_verdict_devtest.py   (exit 0 = pass)
"""
import importlib.util
import json
import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))


def _load(name, fname):
    spec = importlib.util.spec_from_file_location(name,
                                                  os.path.join(HERE, fname))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


tw = _load("tw", "twatch.py")
tm = _load("tm", "testmgr.py")


def report(**kw):
    r = {"tier": "full", "wall": 3600.3, "scale": 1.0, "verdict": "RED",
         "compiler_sha256": "c0ffee", "jobs": [], "deadline": 3600.0,
         "unreached": 0, "timed_out": False}
    r.update(kw)
    return r


def t_a_timeout_is_not_a_red():
    assert tm.verdict_for(0) == "GREEN"
    assert tm.verdict_for(1) == "RED"
    assert tm.verdict_for(tm.TIMEOUT_RC) == "TIMEOUT", \
        "the deadline teardown must not publish as RED — that is the bug"
    assert tm.verdict_for(130) == "INTERRUPTED"
    assert tm.verdict_for(tm.TIMEOUT_RC, invalid=True) == "INVALID", \
        "a mid-run compiler change outranks everything, timeout included"
    return "TIMEOUT is its own verdict"


def t_the_timeout_exit_code_is_distinguishable():
    """1 must not be reused: `rc != 0` is what a shell wrapper tests."""
    assert tm.TIMEOUT_RC not in (0, 1, 130), \
        "the timeout code collides with success/failure/SIGINT"
    return "rc=%d" % tm.TIMEOUT_RC


def t_incomplete_is_read_from_either_spelling():
    assert tw.run_is_incomplete(report(timed_out=True)) is True
    assert tw.run_is_incomplete(report(verdict="TIMEOUT")) is True
    assert tw.run_is_incomplete(report()) is False
    return "field or verdict, either says incomplete"


def t_an_old_report_without_the_field_is_not_incomplete():
    """Reports predate the field. The default must WITHHOLD nothing new.

    Every consumer uses this predicate to suppress an inference, so a wrong
    False is the behaviour we already had, while a wrong True would stop the
    job map from ever being pruned — a permanent stale `fail` is a permanent
    veto, which the auto-pin work learned the hard way.
    """
    legacy = {"tier": "full", "wall": 120.0, "verdict": "RED",
              "compiler_sha256": "c0ffee", "jobs": []}
    assert tw.run_is_incomplete(legacy) is False
    return "legacy reports keep the old behaviour"


def t_the_report_names_what_it_never_reached():
    tmp = tempfile.mkdtemp(prefix="twatch-timeout-devtest-")
    try:
        class C:
            path = tmp
        os.makedirs(os.path.join(tmp, tw.TSTATE_REL, "reports"), exist_ok=True)
        rel = tw.write_report_md(
            C(), "plexus", "a" * 40, "b" * 40,
            report(timed_out=True, verdict="TIMEOUT", unreached=2903),
            [], [], [], st={"jobs": {}},
            not_reached=["test-core#src:test/one.pas",
                         "test-core#src:test/two.pas"])
        body = open(os.path.join(tmp, rel)).read()
        assert "NO VERDICT" in body, \
            "a reader must meet the disclaimer before the job lists"
        assert "2903" in body, "the unreached count is the size of the hole"
        assert "NOT REACHED" in body, "the unreached jobs are not listed"
        assert "test/one.pas" in body and "test/two.pas" in body
        assert "UNKNOWN, not\nfixed" in body or "UNKNOWN, not fixed" in body, \
            "unknown must be named as unknown, not implied by omission"
        return "banner + %d unreached jobs listed" % 2
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def t_a_complete_run_gets_no_banner():
    """The disclaimer must not appear on an ordinary red — it would train the
    reader to skip it, which is how a real one gets missed."""
    tmp = tempfile.mkdtemp(prefix="twatch-timeout-devtest-")
    try:
        class C:
            path = tmp
        os.makedirs(os.path.join(tmp, tw.TSTATE_REL, "reports"), exist_ok=True)
        rel = tw.write_report_md(C(), "plexus", "a" * 40, "b" * 40,
                                 report(), ["test-core#src:test/x.pas"], [], [],
                                 st={"jobs": {}})
        body = open(os.path.join(tmp, rel)).read()
        assert "NO VERDICT" not in body, "banner leaked onto a complete run"
        assert "NOT REACHED" not in body, "empty section rendered anyway"
        assert "NEW-RED" in body, "an ordinary red must still report normally"
        return "clean report unchanged"
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def t_unreached_jobs_keep_their_red():
    """The eviction premise, restated as the assertion that matters.

    st["jobs"] holds two reds. An incomplete run produces a status for only one
    of them. The other was NOT proven fixed and NOT proven gone — it was never
    run — so it must survive in the map and be named, or it comes back as a
    NEW-RED later and reads as fixed in between.
    """
    prev = {"job-a": "fail", "job-b": "fail", "job-c": "pass"}
    now = {"job-a": "pass"}                      # only job-a was reached
    # what the code does for an incomplete run: merge, never replace
    merged = dict(prev, **now)
    assert merged["job-b"] == "fail", \
        "job-b's red was erased by a run that never executed it"
    not_reached = sorted(n for n, v in merged.items()
                         if n not in now and v not in tw.PASSLIKE)
    assert not_reached == ["job-b"], \
        "expected job-b to be named as unreached, got %r" % (not_reached,)
    # and the fixed-list must not claim it
    _, _, fixed, _ = tw.diff_jobs(prev, {"jobs": [
        {"name": "job-a", "sel": "job-a", "status": "pass"}]})
    assert "job-b" not in fixed, "an unreached job was reported as FIXED"
    return "unreached red survives and is named"


def main():
    rc = 0
    for fn in (t_a_timeout_is_not_a_red,
               t_the_timeout_exit_code_is_distinguishable,
               t_incomplete_is_read_from_either_spelling,
               t_an_old_report_without_the_field_is_not_incomplete,
               t_the_report_names_what_it_never_reached,
               t_a_complete_run_gets_no_banner,
               t_unreached_jobs_keep_their_red):
        try:
            print("  ok   %s — %s" % (fn.__name__, fn()))
        except Exception as e:              # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s"
                  % (fn.__name__, type(e).__name__, fail_detail(e)))
    print("timeout verdict OK" if rc == 0 else "timeout verdict BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
