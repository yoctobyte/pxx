#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""The run archive must name EVERY skipped job, not only the coverage holes.

Why: `runs-<host>.ndjson` recorded `skips` (a count), `skip_holes` (a count)
and `skip_hole_jobs` (names).  The names were added because "a bare
`skip_holes: 1` says something did not run and cannot say what, and the report
md that names it is missing for ~8% of runs".  That argument applies word for
word to the skips that are NOT holes, and they were left unnamed -- so on
6d04b14cd88d (seven, full) the archive named 2 of 7.

Naming is INDEPENDENT of classification, which is the point.  Whether a skip is
a coverage hole is the classifier's judgement and it changes -- frankB found
that five of that run's seven were uncounted through a prefix mismatch, not
through being self-skips at all.  Whether it is RECORDED should not depend on
that judgement being right, because the whole reason to record it is so a wrong
judgement is visible afterwards.

A self-skipping recipe is correctly not a coverage hole; SKIP_HOLE_PREFIXES is
deliberate and the harness does not get to overrule a recipe's own guard.  This
file does not reclassify anything, and asserts no hole COUNT that a legitimate
widening of that tuple would break.
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import testmgr  # noqa: E402


class _J(object):
    def __init__(self, name, status, reason):
        self.name, self.status, self.skip_reason = name, status, reason


def _archive_skip_jobs(report):
    """The expression twatch.py writes into the ndjson row, verbatim."""
    return sorted(n
                  for v in (((report.get("skips") or {}).get("by_reason"))
                            or {}).values()
                  for n in v)


def case_names_every_skip_not_only_holes():
    """Drawn from the REAL run, 6d04b14cd88d on seven, not from invented ones.

    The first fixture here guessed that the five uncounted skips were recipe
    self-skips.  They were not: frankB established that all seven are
    harness-originated, and the five are `host dev dependency absent:` (gtk),
    uncounted because that prefix was in no classifier list at all.  The
    guessed population passed this test and would have passed it whatever the
    classifier did, which is a control drawn from the wrong population --
    exactly what it was written to guard against.

    Hole COUNTS are deliberately not asserted here.  They are the classifier's
    property, they are frankB's to change, and pinning them in this file would
    make a correct widening of SKIP_HOLE_PREFIXES fail somebody else's test.
    What is asserted is the property this field exists for: every skip is
    NAMED, whatever it is classified as.
    """
    jobs = [_J("test-zlib#00", "skip",
               "corpus absent: library_candidates/zlib."),
            _J("test-core#1228", "skip",
               "host capability absent: rdrand - this CPU does not have it"),
            _J("test-core#1819", "skip",
               "host dev dependency absent: compiler/gtk.h - this box does "
               "not have it, so that is coverage this box is not providing"),
            _J("test-core#1820", "skip",
               "host dev dependency absent: compiler/gtk.h - this box does "
               "not have it, so that is coverage this box is not providing"),
            _J("test-core#1821", "skip",
               "host dev dependency absent: compiler/gtk.h - this box does "
               "not have it, so that is coverage this box is not providing"),
            _J("test-core#1822", "skip",
               "host dev dependency absent: compiler/gtk.h - this box does "
               "not have it, so that is coverage this box is not providing"),
            _J("test-core#1824", "skip",
               "host dev dependency absent: compiler/gtk.h - this box does "
               "not have it, so that is coverage this box is not providing"),
            _J("test-core#0001", "pass", None)]
    summary = testmgr.skip_summary(jobs)
    report = {"skips": summary}

    assert summary["count"] == 7, summary["count"]

    named = _archive_skip_jobs(report)
    assert len(named) == 7, "archive named %d of 7: %s" % (len(named), named)

    # Superset of the holes, by construction -- the property a consumer relies
    # on to avoid joining two fields.
    for h in summary["hole_jobs"]:
        assert h in named, "%s is a hole but unnamed in skip_jobs" % h

    # And a passing job is never in it.
    assert "test-core#0001" not in named, named


def case_self_skips_stay_out_of_the_hole_count():
    """The POSITIVE CONTROL for the half that must NOT change.

    If someone "fixes" this by folding self-skips into SKIP_HOLE_PREFIXES, the
    hole count stops meaning "the harness failed to cover this" and starts
    meaning "something did not run" -- which is what the single hardcoded
    "(corpus absent)" label did to the FPC canary skips for seven weeks.
    """
    jobs = [_J("a#00", "skip", "a: SKIP - the recipe guarded itself out"),
            _J("b#00", "skip", "corpus absent: library_candidates/zlib")]
    s = testmgr.skip_summary(jobs)
    assert s["count"] == 2, s["count"]
    assert s["coverage_holes"] == 1, s["coverage_holes"]
    assert s["hole_jobs"] == ["b#00"], s["hole_jobs"]
    assert _archive_skip_jobs({"skips": s}) == ["a#00", "b#00"]


def case_absent_skips_field_does_not_crash_the_writer():
    """Rows before this change have no `skips` at all: absent means not known."""
    assert _archive_skip_jobs({}) == []
    assert _archive_skip_jobs({"skips": None}) == []
    assert _archive_skip_jobs({"skips": {}}) == []


def main():
    fails = 0
    for name, fn in sorted(globals().items()):
        if not name.startswith("case_"):
            continue
        try:
            fn()
            print("  ok   %s" % name)
        except AssertionError as e:
            fails += 1
            print("  FAIL %s: %s" % (name, e))
    print("twatch-skip-jobs: %d failure(s)" % fails)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
