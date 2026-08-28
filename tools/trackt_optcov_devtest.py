#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: "no opt run covers this" and "I could not check" are different answers.

`trackt optcov <commit>` answers the question an -O3 -> -O2 promotion asks:
is there any recorded `opt` run whose tree already contained this pass? The
coordinator replaced a hard promotion gate with exactly that citation on
2026-08-28, and a citation nobody can produce mechanically is a gate wearing a
different hat.

The failure mode this file exists for is the one that makes a promotion look
justified when it is not: an UNCHECKABLE run (its sha absent from this
checkout -- unfetched, or rebased away) silently counted as a miss, or worse as
a hit. Unknowns are counted and reported separately, because only one of "no
run covers this" and "I could not check 40 of them" should stop a promotion.

The second guard is the archive-ordering trap, which has now cost two wrong
readings in one session: `runs-*.ndjson` is append-ordered PER HOST and
concatenated across hosts, so a tail of the concatenation is NOT a
chronological tail. Reading one produced "opt last ran 2026-07-31" on a day it
had run at 09:41.

Run: tools/trackt_optcov_devtest.py   (exit 0 = pass)
"""
import importlib.util
import json
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tt", os.path.join(HERE, "trackt.py"))
tt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tt)


def _r(sha, date, verdict="GREEN"):
    return {"sha": sha, "date": date, "verdict": verdict, "host": "h"}


# ------------------------------------------------------------ the selection --

def t_no_runs_is_not_a_hit():
    hit, unknown = tt.optcov_pick([], lambda s: True)
    assert hit is None and unknown == 0
    return "empty archive yields no citation"


def t_picks_the_first_containing_run():
    runs = [_r("aaa", "2026-08-28"), _r("bbb", "2026-08-27")]
    hit, unknown = tt.optcov_pick(runs, lambda s: s == "bbb")
    assert hit["sha"] == "bbb" and unknown == 0
    return "skips non-containing runs and returns the containing one"


def t_newest_wins_when_several_contain():
    """The list is newest-first, so the first hit is the newest citation."""
    runs = [_r("new", "2026-08-28"), _r("old", "2026-08-01")]
    hit, _ = tt.optcov_pick(runs, lambda s: True)
    assert hit["sha"] == "new"
    return "newest containing run is the one cited"


def t_uncheckable_is_counted_not_missed():
    """A run whose sha is absent must not silently read as 'does not contain'.

    This is the guard that matters: a promotion reading 'NOT swept' when the
    truth is 'I could not look' is a wrong answer that looks like a careful
    one.
    """
    runs = [_r("gone", "2026-08-28"), _r("here", "2026-08-27")]
    hit, unknown = tt.optcov_pick(runs, lambda s: None if s == "gone" else True)
    assert hit["sha"] == "here", "an unknown run swallowed the real hit"
    assert unknown == 1, "the unchecked run was not reported"
    return "unknowns are counted, and do not hide a later hit"


def t_all_uncheckable_reports_no_hit_and_the_count():
    runs = [_r("x", "2026-08-28"), _r("y", "2026-08-27")]
    hit, unknown = tt.optcov_pick(runs, lambda s: None)
    assert hit is None and unknown == 2
    return "all-unknown is distinguishable from all-miss"


def t_a_miss_reports_zero_unknown():
    """The two answers must be separable in BOTH directions."""
    runs = [_r("x", "2026-08-28")]
    hit, unknown = tt.optcov_pick(runs, lambda s: False)
    assert hit is None and unknown == 0
    return "a genuine miss carries no unknown count"


# -------------------------------------------------------------- the archive --

def t_runs_are_sorted_by_date_not_file_order():
    """The concatenation-order trap, which has cost two wrong readings.

    Two hosts, each append-ordered, whose interleaving by date differs from
    their concatenation. The newest overall lives in the file that sorts
    FIRST by name, so a naive read returns the wrong 'newest'.
    """
    with tempfile.TemporaryDirectory() as d:
        ts = os.path.join(d, "devdocs", "progress", "tstate")
        os.makedirs(ts)
        with open(os.path.join(ts, "runs-aaa.ndjson"), "w") as f:
            f.write(json.dumps({"tier": "opt", "sha": "early",
                                "date": "2026-07-11T00:00:00Z"}) + "\n")
            f.write(json.dumps({"tier": "opt", "sha": "newest",
                                "date": "2026-08-28T09:41:46Z"}) + "\n")
        with open(os.path.join(ts, "runs-zzz.ndjson"), "w") as f:
            f.write(json.dumps({"tier": "opt", "sha": "middle",
                                "date": "2026-08-01T00:00:00Z"}) + "\n")
        runs = tt.opt_runs(d)
        assert [r["sha"] for r in runs] == ["newest", "middle", "early"], \
            "archive not sorted chronologically: %s" % [r["sha"] for r in runs]
    return "runs sort by date across hosts, not by file order"


def t_only_opt_runs_are_returned():
    with tempfile.TemporaryDirectory() as d:
        ts = os.path.join(d, "devdocs", "progress", "tstate")
        os.makedirs(ts)
        with open(os.path.join(ts, "runs-h.ndjson"), "w") as f:
            for tier in ("full", "native", "opt", "slow"):
                f.write(json.dumps({"tier": tier, "sha": tier,
                                    "date": "2026-08-28T00:00:00Z"}) + "\n")
        runs = tt.opt_runs(d)
        assert [r["sha"] for r in runs] == ["opt"], \
            "a non-opt tier was cited as -O3 coverage: %s" % runs
    return "only opt runs are cited"


def t_a_torn_line_does_not_kill_the_query():
    """The archive is appended live; the last line can be partial."""
    with tempfile.TemporaryDirectory() as d:
        ts = os.path.join(d, "devdocs", "progress", "tstate")
        os.makedirs(ts)
        with open(os.path.join(ts, "runs-h.ndjson"), "w") as f:
            f.write(json.dumps({"tier": "opt", "sha": "good",
                                "date": "2026-08-28T00:00:00Z"}) + "\n")
            f.write('{"tier": "opt", "sha": "tor')
        assert [r["sha"] for r in tt.opt_runs(d)] == ["good"]
    return "a torn trailing line is skipped, not fatal"


def t_missing_archive_is_empty_not_an_exception():
    with tempfile.TemporaryDirectory() as d:
        assert tt.opt_runs(d) == []
    return "absent archive yields no runs"


TESTS = [t_no_runs_is_not_a_hit,
         t_picks_the_first_containing_run,
         t_newest_wins_when_several_contain,
         t_uncheckable_is_counted_not_missed,
         t_all_uncheckable_reports_no_hit_and_the_count,
         t_a_miss_reports_zero_unknown,
         t_runs_are_sorted_by_date_not_file_order,
         t_only_opt_runs_are_returned,
         t_a_torn_line_does_not_kill_the_query,
         t_missing_archive_is_empty_not_an_exception]


def main():
    rc = 0
    print("optcov devtest (%d guards)" % len(TESTS))
    for fn in TESTS:
        try:
            print("  ok   %s — %s" % (fn.__name__, fn()))
        except Exception as e:              # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s"
                  % (fn.__name__, type(e).__name__, fail_detail(e)))
    print("optcov OK" if rc == 0 else "optcov BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
