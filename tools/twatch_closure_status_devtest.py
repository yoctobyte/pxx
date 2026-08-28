#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a regression close records WHY it closed, and never overclaims.

`reg_open()` asks one question — is the merged status still red — and both
`pass` and `skip` answer no. So an entry closed identically whether the job
started PASSING or merely stopped RUNNING.

That was not academic. The auto-close wrote "`<job>` passes at <sha>" into the
ticket it retired, unconditionally, and `done/` is where a finding stops being
read. A job whose corpus went missing got a permanent written claim that it
passed — the false-fixed claim, in prose, in the record.

Same information gap as [[bug-t-a-skipped-job-is-passlike-so-it-becomes-a-false-
last-good]], one level up in the data model: a skip and a pass are both simply
"not red".

This does NOT change what closes — whether a skip *should* close is a live Track
U question. It changes only what the close CLAIMS, which loses nothing either
way, which is why it is not one of that decision's options.

Guards, and each names the break it catches:
  * a skip-close must not say "passes"      (the original defect)
  * a pass-close must still say "passes"    (the over-correction)
  * an unstamped entry must read as before  (migration)

Run: tools/twatch_closure_status_devtest.py   (exit 0 = pass)
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

JOB = "lib-test#src:test/lib_synapse.pas"


def t_a_pass_close_is_recorded_as_pass():
    got = tw.closure_status({"job": JOB}, {JOB: "pass"})
    assert got == "pass", got
    return "pass -> 'pass'"


def t_a_skip_close_is_recorded_as_skip():
    """THE defect. The entry closes either way; only the record differs."""
    got = tw.closure_status({"job": JOB}, {JOB: "skip"})
    assert got == "skip", (
        "a job that stopped RUNNING must not be recorded as having passed: %r"
        % got)
    return "skip -> 'skip', not 'pass'"


def t_a_vanished_job_is_gone_not_passed():
    got = tw.closure_status({"job": JOB}, {}, gone=frozenset([JOB]))
    assert got == "gone", (
        "a job that no longer exists did not pass and did not skip: %r" % got)
    return "gone outranks the rest"


def t_a_cascade_needs_every_job_to_pass():
    """A cascade closing on a mixture must not read as a clean pass."""
    both = tw.closure_status({"job": "cascade@x", "cascade": ["a", "b"]},
                             {"a": "pass", "b": "skip"})
    assert both == "mixed", "a cascade with one skip is not a pass: %r" % both
    allp = tw.closure_status({"job": "cascade@x", "cascade": ["a", "b"]},
                             {"a": "pass", "b": "pass"})
    assert allp == "pass", allp
    alls = tw.closure_status({"job": "cascade@x", "cascade": ["a", "b"]},
                             {"a": "skip", "b": "skip"})
    assert alls == "skip", alls
    return "cascade: all-pass, all-skip and mixed are distinct"


def t_a_cascade_of_vanished_jobs_is_gone():
    got = tw.closure_status({"job": "cascade@x", "cascade": ["a", "b"]},
                            {}, gone=frozenset(["a", "b"]))
    assert got == "gone", got
    return "a cascade whose jobs all vanished is gone, not passed"


def t_it_does_not_change_WHAT_closes():
    """The scope line. reg_open's verdict must be untouched — this ticket
    records the reason, it does not relitigate the policy."""
    assert not tw.reg_open({"job": JOB}, {JOB: "skip"}), (
        "red -> skip must still close; changing that is the Track U decision, "
        "not this chore")
    assert tw.reg_open({"job": JOB}, {JOB: "fail"}), "a real fail stays open"
    return "reg_open's verdict is unchanged"


def _close_line(closed_by):
    """The branch of close_stub_tickets that composes the log sentence."""
    src = open(os.path.join(HERE, "twatch.py")).read()
    i = src.index('why = r.get("closed_by")')
    return src[i:src.index("Reopening is by a fresh", i)]


def t_the_skip_wording_refuses_to_claim_a_pass():
    seg = _close_line("skip")
    assert 'if why == "skip":' in seg, "there must be a skip branch"
    skip_branch = seg[seg.index('if why == "skip":'):seg.index('elif why == "gone"')]
    assert "passes at" not in skip_branch, (
        "the skip branch must NOT say 'passes at' — that is the defect: %s"
        % skip_branch.strip()[:200])
    assert "NOT that the bug is fixed" in skip_branch, (
        "it must say what the close is not evidence of")
    return "the skip wording never claims a pass"


def t_the_pass_wording_is_preserved():
    """The over-correction. If every close hedges, the honest ones stop
    carrying information and readers learn to skim the line."""
    seg = _close_line("pass")
    tail = seg[seg.index("else:"):]
    assert "passes at" in tail, (
        "a genuine pass must still be stated plainly: %s" % tail.strip()[:200])
    assert "SKIPPED" not in tail, "the pass branch must not hedge"
    return "a real pass still reads as a pass"


def t_an_unstamped_entry_reads_as_before():
    """MIGRATION. Entries written by an older watcher have no closed_by, and
    must fall through to the original wording rather than to a hedge."""
    seg = _close_line(None)
    tail = seg[seg.index("else:"):]
    assert "passes at" in tail
    assert seg.index("else:") > seg.index('elif why == "mixed"'), (
        "the unstamped case must be the final else, so absent means 'as before'")
    return "absent closed_by -> the original wording"


def t_the_stamp_is_applied_where_the_predicate_runs():
    src = open(os.path.join(HERE, "twatch.py")).read()
    seg = src[src.index("closed_regs = ["):]
    seg = seg[:seg.index("srcmap =")]
    assert 'r["closed_by"] = closure_status(' in seg, (
        "closed entries must be stamped beside the reg_open filter that closed "
        "them, not re-derived by the consumer")
    return "stamped where authoritative and gone are in hand"


def main():
    rc = 0
    for fn in (t_a_pass_close_is_recorded_as_pass,
               t_a_skip_close_is_recorded_as_skip,
               t_a_vanished_job_is_gone_not_passed,
               t_a_cascade_needs_every_job_to_pass,
               t_a_cascade_of_vanished_jobs_is_gone,
               t_it_does_not_change_WHAT_closes,
               t_the_skip_wording_refuses_to_claim_a_pass,
               t_the_pass_wording_is_preserved,
               t_an_unstamped_entry_reads_as_before,
               t_the_stamp_is_applied_where_the_predicate_runs):
        try:
            print("  ok   %s — %s" % (fn.__name__, fn()))
        except Exception as e:              # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s"
                  % (fn.__name__, type(e).__name__, fail_detail(e)))
    print("closure-status OK" if rc == 0 else "closure-status BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
