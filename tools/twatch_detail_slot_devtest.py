#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: the single `## first failure:` slot goes to a NEW-RED when one exists.

A report carries exactly one detail block -- diagnostics plus a log tail. It used
to go to the first failure in JOB ORDER, so a permanently-red job won it on every
report forever, and the news was starved of detail exactly when it mattered most.
Measured 2026-09-01: a report with 7 failures spent its slot on a threads job red
in 5 of 5 recent runs, while four brand-new `test_managed_dynarray_field_leaks`
reds got a 160-char tail apiece, cut mid-word. Three agents then spent an
afternoon inferring what the block would have said.

The fence these cases draw is narrow on purpose. Preferring a new red decides
only who wins when a new red and a still-red COMPETE; with no new red the
still-red keeps the slot, so no report loses coverage it used to have. Four of
the five cases below assert exactly that, and they pass against the pre-change
code too -- two of the six cases separate this code from the code before it
(`..._outranks_a_still_red...` and `..._heading_does_not_claim_job_order`),
and that asymmetry is the point rather than an accident -- checked by
running these cases against the pre-change file, not by reasoning.

Run: tools/twatch_detail_slot_devtest.py   (exit 0 = pass)
"""
import glob
import importlib.util
import os
import re
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tw", os.path.join(HERE,
                                                                "twatch.py"))
tw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tw)


def job(name, status):
    return {"name": name, "sel": name, "status": status, "src": "", "log": None}


# Job ORDER is the axis under test: STILL sorts first in every case below, so
# any case where NEW is selected can only be the new-red preference.
STILL = job("test-threads#01", "fail")      # red for days
NEW = job("test-core#42", "fail")           # the news
GREEN = job("test-core#07", "pass")

K = tw.job_key


def selected(jobs, new_red):
    """Run the REAL emitter and read the slot back out of the written file.

    Not a re-implementation of the selection: the report markdown is the
    artifact a human reads, and a fixture of it would only test my intent.
    """
    tmp = tempfile.mkdtemp(prefix="twdetail")
    try:
        clone = type("C", (), {"path": tmp})()
        report = {"tier": "full", "wall": 1, "scale": 1.0, "verdict": "RED",
                  "jobs": jobs, "skips": {"count": 0, "coverage_holes": 0},
                  "flaky": [], "compiler_sha256": "deadbeef"}
        tw.write_report_md(clone, "host", "a" * 40, "b" * 40, report,
                           new_red, [], [K(STILL)])
        found = glob.glob(os.path.join(tmp, tw.TSTATE_REL, "reports", "*.md"))
        assert len(found) == 1, "expected one report, got %r" % (found,)
        body = open(found[0]).read()
        m = re.search(r"^## (?:failure detail|first failure): (\S+)",
                      body, re.M)
        return m.group(1) if m else None
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def rendered(jobs, new_red):
    """The report body itself, for cases about wording rather than choice."""
    tmp = tempfile.mkdtemp(prefix="twdetail")
    try:
        clone = type("C", (), {"path": tmp})()
        report = {"tier": "full", "wall": 1, "scale": 1.0,
                  "verdict": "RED", "jobs": jobs, "flaky": [],
                  "skips": {"count": 0, "coverage_holes": 0},
                  "compiler_sha256": "deadbeef"}
        tw.write_report_md(clone, "host", "a" * 40, "b" * 40, report,
                           new_red, [], [K(STILL)])
        found = glob.glob(os.path.join(tmp, tw.TSTATE_REL,
                                       "reports", "*.md"))
        assert len(found) == 1, "expected one report, got %r" % (found,)
        return open(found[0]).read()
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def t_a_new_red_outranks_a_still_red_that_sorts_first():
    got = selected([STILL, GREEN, NEW], [K(NEW)])
    assert got == K(NEW), "slot went to %r, not the new red %r" % (got, K(NEW))
    return "the news wins the slot"


def t_with_no_new_red_the_still_red_keeps_the_slot():
    got = selected([STILL, GREEN], [])
    assert got == K(STILL), "a still-red report lost its detail block (%r)" % got
    return "no report loses coverage it used to have"


def t_a_new_red_from_another_report_does_not_blank_the_slot():
    """new_red is computed against the PARENT and can name a job this run did
    not schedule (a tier change, a renamed job). That must fall back, not
    produce a report with no detail at all."""
    got = selected([STILL, GREEN], ["test-gone#99"])
    assert got == K(STILL), "a stale new_red key emptied the slot (%r)" % got
    return "an unmatched new_red key falls back"


def t_a_new_red_key_naming_a_passing_job_is_not_selected():
    """The status filter has to survive the preference: a job that PASSED on a
    retry can appear in new_red, and a `## first failure:` naming a pass is
    worse than naming the wrong failure."""
    got = selected([STILL, GREEN], [K(GREEN)])
    assert got == K(STILL), "slot went to a passing job (%r)" % got
    return "a passing job cannot take the failure slot"


def t_an_all_green_report_has_no_detail_block():
    got = selected([GREEN], [])
    assert got is None, "green report grew a first-failure block (%r)" % got
    return "green stays green"


def t_the_heading_does_not_claim_job_order():
    """The block is chosen, so a heading saying "first failure" would be a
    true-sounding name for a different thing. Both halves are asserted: the
    false wording is gone AND the report says which rule picked the job, so a
    reader never has to infer it from the job list."""
    body = rendered([STILL, GREEN, NEW], [K(NEW)])
    assert "## first failure:" not in body, "heading still claims job order"
    assert "## failure detail: %s" % K(NEW) in body, "heading missing:\n" + body
    assert re.search(r"^selected: NEW RED this run$", body, re.M), \
        "no provenance line for a new-red pick:\n" + body

    body = rendered([STILL, GREEN], [])
    assert re.search(r"^selected: first failure in job order; no new red",
                     body, re.M), \
        "no provenance line for a fallback pick:\n" + body
    return "the heading names what was selected, and why"


def main():
    rc = 0
    for fn in (t_a_new_red_outranks_a_still_red_that_sorts_first,
               t_with_no_new_red_the_still_red_keeps_the_slot,
               t_a_new_red_from_another_report_does_not_blank_the_slot,
               t_a_new_red_key_naming_a_passing_job_is_not_selected,
               t_an_all_green_report_has_no_detail_block,
               t_the_heading_does_not_claim_job_order):
        try:
            print("  ok   %s — %s" % (fn.__name__, fn()))
        except Exception as e:              # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s"
                  % (fn.__name__, type(e).__name__, fail_detail(e)))
    print("detail slot OK" if rc == 0 else "detail slot BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
