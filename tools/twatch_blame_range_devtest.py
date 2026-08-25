#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a red is blamed on commits that could actually have caused it.

Measured on the first completed breadth run on `dev`, 2026-08-25. Four NEW-REDs
on full-tier-only jobs — `test-aarch64#…forin_member_access`, `test-uforth#core`
and two `test-pascal-conformance` shards — were filed against a **23-commit**
range, because the parent run was `native`. Those jobs had not executed for
1d15h and ~120 commits.

A too-narrow range is the dangerous direction and it is worth being precise
about why. A bisect over commits that do not contain the culprit does not fail
and does not say "not found": it narrows, confidently, onto an innocent commit,
and the repo's own rule is that a core-job red is a revert candidate.
`last_covering_sha()` already reasons about this correctly — its docstring says
"a too-wide range costs bisect steps; a too-narrow one can exclude the culprit,
which is the failure that matters" — but it was gated on the range being EMPTY,
which is the symptom that happened to be noticed first (one sha re-tested at a
widening tier), not the general case.

Run: tools/twatch_blame_range_devtest.py   (exit 0 = pass)
"""
import importlib.util
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tw", os.path.join(HERE,
                                                                "twatch.py"))
tw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tw)

AARCH = "test-aarch64#src:test/test_forin_member_access.pas"
CORE = "test-core#src:test/test_ansistring.pas"
OPT = "optdiff#shard5/6"


def st_with(parent_tier, job_tier):
    return {"last": {"tier": parent_tier, "sha": "d" * 40},
            "job_tier": dict(job_tier)}


def t_the_measured_case_a_full_job_after_a_native_parent():
    st = st_with("native", {AARCH: "full"})
    assert not tw.parent_ran_job(st, AARCH, "full"), \
        "a full-tier-only job was blamed on the range since a NATIVE parent — " \
        "this is the exact 23-vs-120 commit misattribution"
    return "full job + native parent -> parent range refused"


def t_a_job_the_parent_did_run_keeps_the_narrow_range():
    """The narrow range is RIGHT when it is right. Widening every range would
    trade a wrong bisect for a slow one on every ordinary red."""
    st = st_with("native", {CORE: "native"})
    assert tw.parent_ran_job(st, CORE, "full"), \
        "a job the parent actually ran was needlessly widened"
    return "native job + native parent -> parent range kept"


def t_a_full_parent_covers_a_full_job():
    st = st_with("full", {AARCH: "full"})
    assert tw.parent_ran_job(st, AARCH, "full")
    return "full parent covers it"


def t_opt_is_disjoint_and_only_opt_answers_for_it():
    """covered_tiers("opt") == {"opt"} — a full run does not contain optdiff, so
    a full parent must not bound an opt job's range. This is why the
    optdiff#shard8-12 miscompile sat two days unattributed."""
    st = st_with("full", {OPT: "opt"})
    assert not tw.parent_ran_job(st, OPT, "opt"), \
        "a full parent was accepted as covering an opt job"
    st = st_with("opt", {OPT: "opt"})
    assert tw.parent_ran_job(st, OPT, "opt")
    return "only an opt run answers for opt"


def t_an_unknown_job_falls_back_to_this_run_s_tier():
    """A job with no recorded history — first run, or renamed. It must not
    raise, and it must not silently claim the parent covered it."""
    st = st_with("native", {})
    assert tw.job_bounding_tier(st, "brand-new#00", "full") == "full"
    assert not tw.parent_ran_job(st, "brand-new#00", "full"), \
        "an unknown job claimed parent coverage it cannot have"
    return "unknown job -> this run's tier, no parent claim"


def t_a_host_with_no_parent_run_claims_nothing():
    assert not tw.parent_ran_job({}, AARCH, "full")
    assert not tw.parent_ran_job({"last": {}}, AARCH, "full")
    return "no parent, no coverage claim"


def main():
    rc = 0
    for fn in (t_the_measured_case_a_full_job_after_a_native_parent,
               t_a_job_the_parent_did_run_keeps_the_narrow_range,
               t_a_full_parent_covers_a_full_job,
               t_opt_is_disjoint_and_only_opt_answers_for_it,
               t_an_unknown_job_falls_back_to_this_run_s_tier,
               t_a_host_with_no_parent_run_claims_nothing):
        try:
            print("  ok   %s — %s" % (fn.__name__, fn()))
        except Exception as e:              # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s"
                  % (fn.__name__, type(e).__name__, fail_detail(e)))
    print("blame range OK" if rc == 0 else "blame range BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
