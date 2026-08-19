#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest for closing ledger entries whose job key no longer exists.

bug-t-ledger-entry-outlives-the-job-key-it-names. `reg_open` closes a per-job
entry only when its key turns up in `fixed`, and `fixed` can only name keys a
run REPORTED — so a key that stops existing strands its entry forever, asking
agents to act on a job nothing can run. That is the quiet-host problem reached
through job identity instead of host identity.

Keys stop existing routinely: a test is renamed or deleted, or the `@N` suffix
`assign_selectors` adds shifts because a source's occurrence count inside its
target changed. On 2026-08-04 one nilpy source sat in the Makefile three times
(an agent had overwritten an existing test with a same-named new one) and
reverted hours later; 110 of xeon's keys carry an `@N` today.

The trap this must not fall into is the one that produced the opt-eviction bug:
"this run did not report the key" is NOT "the key is gone". Absence only counts
against a run whose tier COVERS the key's tier — otherwise a native run would
declare every full-tier job gone.

Pure functions, no clone, no git.
Run: python3 tools/twatch_gone_key_devtest.py
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import twatch  # noqa: E402
from devtest_report import fail_detail  # noqa: E402

JOB = "test-nilpy#src:test/test_nilpy_print_arg_eval_order.npy@1"
LIVE = "test-core#src:test/live.pas"


def state(regs, job_tier):
    return {"open_regressions": regs, "job_tier": job_tier, "jobs": {}}


def entry(job):
    return {"job": job, "bad": "b" * 40, "good": None, "range": ["c" * 40]}


def case_vanished_key_is_gone():
    st = state([entry(JOB)], {JOB: "full"})
    gone = twatch.gone_keys(st, now={LIVE: "pass"}, tier="full")
    assert JOB in gone, gone
    assert not twatch.reg_open(entry(JOB), authoritative={}, gone=gone), \
        "an entry naming a job no tier has any more stayed open"
    return "absent from a covering run -> closed as GONE"


def case_other_tier_is_not_gone():
    """The opt-eviction trap: a native run reports no full-tier jobs, and that
    says nothing about whether they exist."""
    st = state([entry(JOB)], {JOB: "full"})
    gone = twatch.gone_keys(st, now={LIVE: "pass"}, tier="native")
    assert JOB not in gone, "a full-tier key was declared gone by a native run"
    assert twatch.reg_open(entry(JOB), authoritative={}, gone=gone)
    return "full-tier key survives a native run"


def case_opt_is_disjoint():
    """`opt` jobs appear in no other tier, so a full run must not gone-ify them
    — the same asymmetry that made a full run evict opt's verdicts."""
    opt_job = "optdiff#shard5"
    st = state([entry(opt_job)], {opt_job: "opt"})
    gone = twatch.gone_keys(st, now={LIVE: "pass"}, tier="full")
    assert opt_job not in gone, "a full run declared an opt job gone"
    return "opt key survives a full run"


def case_present_and_red_stays_open():
    st = state([entry(JOB)], {JOB: "full"})
    gone = twatch.gone_keys(st, now={JOB: "fail"}, tier="full")
    assert not gone, gone
    assert twatch.reg_open(entry(JOB), authoritative={JOB: "fail"},
                           gone=gone), "a still-red job was closed"
    return "reported and red -> still open"


def case_present_and_fixed_closes_normally():
    """The GONE path must not shadow the ordinary FIXED path."""
    st = state([entry(JOB)], {JOB: "full"})
    gone = twatch.gone_keys(st, now={JOB: "pass"}, tier="full")
    assert not gone
    assert not twatch.reg_open(entry(JOB), authoritative={JOB: "pass"},
                               gone=gone)
    return "reported and passing -> closed as FIXED"


def case_cascade_ignores_gone_members():
    """A swept job that no longer exists must not pin a cascade open; if every
    job it named is gone, the cascade goes with them."""
    a, b = "test-core#src:test/a.pas", "test-core#src:test/b.pas"
    casc = {"job": "cascade@abc123", "cascade": [a, b], "bad": "b" * 40,
            "range": []}
    st = state([casc], {a: "full", b: "full"})
    # `a` still red, `b` vanished -> stays open because of `a`
    gone = twatch.gone_keys(st, now={a: "fail"}, tier="full")
    assert b in gone and a not in gone, gone
    assert twatch.reg_open(casc, authoritative={a: "fail"}, gone=gone)
    # both vanished -> closes
    gone_all = twatch.gone_keys(st, now={LIVE: "pass"}, tier="full")
    assert not twatch.reg_open(casc, authoritative={}, gone=gone_all), \
        "a cascade naming only vanished jobs stayed open forever"
    return "gone members neither pin nor hide the rest"


def case_unknown_tier_defaults_to_covered():
    """State written before job_tier existed has no entry; the eviction rule
    treats that as covered, and this must agree rather than invent a third
    behaviour."""
    st = state([entry(JOB)], {})          # no job_tier at all
    gone = twatch.gone_keys(st, now={LIVE: "pass"}, tier="full")
    assert JOB in gone, "legacy key without job_tier became sticky-forever"
    return "no job_tier -> treated as covered, matching eviction"


CASES = [
    case_vanished_key_is_gone,
    case_other_tier_is_not_gone,
    case_opt_is_disjoint,
    case_present_and_red_stays_open,
    case_present_and_fixed_closes_normally,
    case_cascade_ignores_gone_members,
    case_unknown_tier_defaults_to_covered,
]


def main():
    rc = 0
    for case in CASES:
        name = case.__name__.removeprefix("case_").replace("_", "-")
        try:
            note = case()
        except AssertionError as e:
            print(f"  FAIL {name}: {fail_detail(e)}")
            rc = 1
        else:
            print(f"  ok   {name} — {note}")
    print("gone-key closing OK" if rc == 0 else "gone-key closing BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
