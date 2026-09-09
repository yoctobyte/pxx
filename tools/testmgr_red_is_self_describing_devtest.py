#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a RED must be able to say what broke.

Two defects, one subject: the archive recorded that a job went red and could
not say what, and the field a reader uses to LOCATE the step printed a number
that cannot be true.

1. AN EMPTY LOG IS NOT AN UNREADABLE ONE. job_reason() returns "" and its own
   docstring promises that "" reads as "the log is gone or unreadable, never a
   claim that the job failed for no reason". A red whose log is 0 bytes
   published exactly that "", and the report's failure-detail block came out
   empty. It is a real shape and not a corner: a recipe row asserting with a
   bare `grep -q` prints NOTHING when it fails, and `grep -q` is correct as a
   recipe step and silent as the last thing a failing job does.

2. `line 35 of 10 of the job's recipe`. Job.script() numbers `self.lines` --
   every line, comments included, because failed_step() indexes `lines[i]`.
   step_n counted only the NON-comment lines. Numerator and denominator over
   different sets, in the one field that says where to look. It does not read
   as broken; it reads as "near the end".

WHY THESE ARE ONE FILE. On one bug, in one pass, three separate cheap ways of
locating the failure each named an innocent row -- the tstate reason named
four scripts never implicated, this step number said 35 of 10, and counting
recipe lines by hand landed on a test that passes. None of the three errored.
All three answered. The cost is paid by whoever is debugging something else.

bug-t-a-failing-grep-q-step-leaves-the-archive-unable-to-say-what-broke
Run: tools/testmgr_red_is_self_describing_devtest.py   (exit 0 = pass)
"""
import importlib.util
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tm",
                                              os.path.join(HERE, "testmgr.py"))
tm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tm)

# A job shaped like the one that produced this: a comment, a compile that
# passes, and a bare `grep -q` that fails and prints nothing.
LINES = [
    "# why this row exists, at length, the way real recipes are",
    "# and a second comment line",
    "./compiler/pascal26 test/x.pas /tmp/t/x > /tmp/t/x.log 2>&1",
    'grep -q "the note that is not there" /tmp/t/x.log',
]
GREP_STEP = 3          # index into LINES, comments included


def _job(logbody, step_i=GREP_STEP, lines=None):
    """A Job with a real log and a real .step marker on disk.

    Uses the module's own Job so the guard cannot drift from the code: a
    hand-rolled stub would keep passing after script() stopped numbering the
    list step_n measures.
    """
    d = tempfile.mkdtemp(prefix="tmredselfdesc-")
    j = tm.Job("test-core", 0, list(LINES if lines is None else lines))
    j.logpath = os.path.join(d, "job.log")
    with open(j.logpath, "w") as f:
        f.write(logbody)
    if step_i is not None:
        with open(j.logpath + ".step", "w") as f:
            f.write("%d\n" % step_i)
    j.status = "fail"
    return j


def t_an_empty_log_does_not_publish_as_an_empty_reason():
    j = _job("")
    r = tm.job_reason(j)
    assert r, "a 0-byte log still publishes '' — the archive cannot say what broke"
    assert "printed nothing" in r, "the note does not say the step was silent: %r" % r
    assert "grep -q" in r, "the note does not name the failing step: %r" % r
    return "0-byte log yields a note naming the silent step"


def t_an_all_noise_tail_still_reports_an_error_above_it():
    """NOT THE INTENT, KEPT DELIBERATELY, so it is asserted rather than left as
    a side effect of where a `return` moved.

    job_reason() already scans above the tail for the last substantive error
    when the tail does not diagnose the failure -- but the old code returned ""
    before reaching that scan whenever the tail was ENTIRELY noise, so a log
    naming its error two lines above `make: *** Error 1` published nothing.
    The fpc case that scan was written for has a tail of WARNINGS, which are
    not noise, so it never exposed this.
    """
    j = _job("a.pas(3,1) Error: undefined variable (q)\n"
             "make[1]: *** [Makefile:9: t] Error 1\n"
             "make: *** [Makefile:2: all] Error 2\n")
    r = tm.job_reason(j)
    assert "undefined variable" in r, (
        "an all-noise tail still buries the error above it: %r" % r)
    assert "printed nothing" not in r, "the empty-log note fired on a real log"
    return "an error above an all-noise tail is reported, not swallowed"


def t_a_missing_log_still_reads_as_unknown():
    """The negative control, and it is the one that keeps the fix honest.

    "" must stay reserved for "gone or unreadable". If the empty-log note
    swallowed this case too, every red would claim its step printed nothing --
    including reds whose log the OS reaped, where that is simply false.
    """
    j = _job("")
    os.unlink(j.logpath)
    assert tm.job_reason(j) == "", "an unreadable log stopped reading as unknown"
    j2 = _job("")
    j2.logpath = None
    assert tm.job_reason(j2) == "", "a job that never launched stopped reading as unknown"
    return "gone and never-launched both still publish '' "


def t_a_log_with_content_is_untouched():
    j = _job("error: undefined variable (q)\n")
    r = tm.job_reason(j)
    assert "undefined variable" in r, "the tail stopped being the answer: %r" % r
    assert "printed nothing" not in r, "the empty-log note fired on a non-empty log"
    return "a log that says something still speaks for itself"


def t_an_empty_log_with_no_step_marker_says_so():
    j = _job("", step_i=None)
    r = tm.job_reason(j)
    assert "not recorded" in r, "an unrecorded step is claimed as known: %r" % r
    return "no .step marker reads as 'not recorded', never as a guess"


def t_the_step_citation_cannot_exceed_the_recipe():
    """`line 35 of 10`. The index and the count must be over ONE list."""
    j = _job("")
    row = tm.report_job(j)
    i, n = row["step_i"], row["step_n"]
    assert i is not None, "the failing step was not recorded at all"
    assert 0 <= i < n, ("step citation is impossible: line %d of %d "
                        "(the numerator and denominator are over different "
                        "line sets)" % (i + 1, n))
    assert n == len(LINES), ("step_n is %d for a %d-line recipe — it is "
                             "measuring a different list again" % (n, len(LINES)))
    return "line %d of %d, both over job.lines" % (i + 1, n)


def t_the_comment_lines_are_what_used_to_break_it():
    """The positive control for the citation, drawn from the population that
    produced it: a recipe whose comments outnumber its commands is exactly
    where the old count went impossible, and a recipe with no comments at all
    would have passed the old code too."""
    old_n = sum(1 for l in LINES if not l.strip().startswith("#"))
    assert old_n < GREP_STEP + 1, (
        "this fixture no longer reproduces the defect: the old denominator "
        "(%d) does not undercut the index (%d), so the control has stopped "
        "controlling" % (old_n, GREP_STEP + 1))
    return ("old rule would have printed line %d of %d — impossible"
            % (GREP_STEP + 1, old_n))


def t_script_numbers_the_same_list_step_n_counts():
    """AIM THE GUARD AT THE CODE, not at the fixture. Everything above would
    keep passing if script() started numbering a filtered list, because both
    halves would move together in the report and only the LINE TEXT would be
    wrong -- a silent misattribution, which is the defect one layer down.
    """
    j = _job("")
    body = j.script()
    marker = "echo %d > %s" % (GREP_STEP, j.logpath + ".step")
    assert marker in body, (
        "script() no longer writes the index of the grep line as %d — it is "
        "numbering a different list than step_n counts" % GREP_STEP)
    i, line = tm.failed_step(j)
    assert line == LINES[GREP_STEP], (
        "failed_step resolved index %d to %r, not the grep row" % (i, line))
    return "script(), failed_step() and step_n all index job.lines"


def t_a_noise_only_log_is_not_claimed_to_be_empty():
    """THE NEGATIVE CONTROL THAT CAUGHT THE FIRST VERSION OF THIS FIX.

    `make: *** [t] Error 1` is noise -- it carries nothing the job's status
    and name do not already say -- and job_reason_devtest.py has always
    asserted a noise-only log yields "". The first version of the empty-log
    note fired here too and said "the failing step printed nothing" about a
    log that had printed exactly that line: a second false statement in the
    field this whole change exists to stop lying in.
    """
    j = _job("make: *** [test-core] Error 1\n")
    assert tm.job_reason(j) == "", (
        "a noise-only log now claims the step printed nothing: %r"
        % tm.job_reason(j))
    return "noise-only still publishes '' — unchanged and argued elsewhere"


def _rendered(job):
    """The report markdown twatch would write for one red job.

    Drives the real write_report_md rather than grepping its constants: a
    branch that exists and is unreachable passes a constants check and fails
    the reader, which is the defect class this whole file is about.
    """
    import glob
    import shutil
    spec2 = importlib.util.spec_from_file_location(
        "tw", os.path.join(HERE, "twatch.py"))
    tw = importlib.util.module_from_spec(spec2)
    spec2.loader.exec_module(tw)
    tmp = tempfile.mkdtemp(prefix="tmredselfdesc-rep-")
    try:
        clone = type("C", (), {"path": tmp})()
        report = {"tier": "full", "wall": 1, "scale": 1.0, "verdict": "RED",
                  "jobs": [job], "flaky": [], "compiler_sha256": "deadbeef",
                  "skips": {"count": 0, "coverage_holes": 0}}
        tw.write_report_md(clone, "host", "a" * 40, "b" * 40, report,
                           [job["sel"]], [], [])
        found = glob.glob(os.path.join(tmp, tw.TSTATE_REL, "reports", "*.md"))
        assert len(found) == 1, "expected one report, got %r" % (found,)
        return open(found[0]).read()
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def t_the_report_block_never_publishes_a_silent_empty_fence():
    """twatch's `## failure detail` block reads the LOG FILE, not the report,
    so fixing job_reason alone leaves the block a bare empty ``` pair -- and
    that block is what a reader opens first."""
    j = _job("")
    row = tm.report_job(j)
    body = _rendered(row)
    assert "## failure detail" in body, "no detail block at all:\n" + body
    assert "the job log is EMPTY" in body, (
        "a 0-byte log still publishes a silent block:\n" + body)
    assert "grep -q" in body, (
        "the block does not name the failing step:\n" + body)
    assert "```\n```" not in body, "an empty fenced block survived:\n" + body
    return "an empty log renders a note plus the step, not a bare fence"


def t_a_reaped_log_says_so_rather_than_nothing():
    """The other way this block goes silent, and the one that grows with age:
    `log` is a path in a temp dir the OS reaps, so every report read more than
    LOGDIR_KEEP_SECS after its run takes this branch."""
    j = _job("real output that will not survive\n")
    row = tm.report_job(j)
    os.unlink(j.logpath)
    body = _rendered(row)
    assert "no longer exists" in body, (
        "a reaped log renders nothing after the repro line:\n" + body)
    assert "grep -q" in body, "and it does not fall back to the step either"
    return "a reaped log names itself and falls back to the report's fields"


def t_a_log_with_output_still_renders_the_log():
    """The negative control for both rows above: the ordinary case must not
    have acquired a note it does not need."""
    j = _job("error: undefined variable (q)\n")
    body = _rendered(tm.report_job(j))
    assert "undefined variable" in body, "the log stopped being rendered:\n" + body
    assert "the job log is EMPTY" not in body, "the empty note fired on a real log"
    return "a log with output is rendered exactly as before"


def main():
    rc = 0
    for fn in (t_an_empty_log_does_not_publish_as_an_empty_reason,
               t_a_noise_only_log_is_not_claimed_to_be_empty,
               t_an_all_noise_tail_still_reports_an_error_above_it,
               t_the_report_block_never_publishes_a_silent_empty_fence,
               t_a_reaped_log_says_so_rather_than_nothing,
               t_a_log_with_output_still_renders_the_log,
               t_a_missing_log_still_reads_as_unknown,
               t_a_log_with_content_is_untouched,
               t_an_empty_log_with_no_step_marker_says_so,
               t_the_step_citation_cannot_exceed_the_recipe,
               t_the_comment_lines_are_what_used_to_break_it,
               t_script_numbers_the_same_list_step_n_counts):
        try:
            print("  ok   %s — %s" % (fn.__name__, fn()))
        except Exception as e:              # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s"
                  % (fn.__name__, type(e).__name__, fail_detail(e)))
    print("red_is_self_describing OK" if rc == 0
          else "red_is_self_describing BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
