#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a TIMED-OUT sha must not count as covered.

`test_sha()` records `st["last"]` for every run that produced a report,
including a torn-down one -- correctly, because it IS the parent for the next
run's diff and the baseline the job map is built against. Dropping it would
re-attribute every red in between, a much larger error than the one being
fixed. So the record stays and staleness gets a field to ask about.

The defect this guards: staleness asked "is there a record for this sha?", and
a timeout leaves one. So the one shape of run that proves the LEAST -- torn
down with jobs undecided -- was the one that most effectively silenced the
request for more. The verdict has been honest since 2026-08-25 (`TIMEOUT`,
`timed_out: true`, a NOT REACHED list); this is the separate mechanism that
never looked at it.

It shows up quietly: `--status` reporting UP with a sha that has no complete run
behind it. No red to notice.

Run: tools/twatch_timeout_staleness_devtest.py   (exit 0 = pass)
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


def coverage(hosts):
    """The tested/incomplete split exactly as status() computes it.

    Mirrored rather than called: status() wants a repo, a ref and a fetch. The
    guard below asserts the mirror has not drifted from the original.
    """
    tested, incomplete = set(), set()
    for st in hosts:
        recs = list(st.get("history") or [])
        if st.get("last"):
            recs.append(st["last"])
        for r in recs:
            sha = r.get("sha")
            if not sha:
                continue
            if r.get("timed_out") or r.get("verdict") == "TIMEOUT":
                incomplete.add(sha)
            else:
                tested.add(sha)
    incomplete -= tested
    return tested, incomplete


def t_the_mirror_matches_the_real_split():
    """A hand-copied rule is a second path, and a second path is what this
    whole ticket family is about. Assert the copy still reflects the source."""
    src = open(os.path.join(HERE, "twatch.py")).read()
    seg = src.split("tested, incomplete = set(), set()", 1)[1][:900]
    for probe in ('r.get("timed_out") or r.get("verdict") == "TIMEOUT"',
                  "incomplete -= tested",
                  'recs.append(st["last"])'):
        assert probe in seg, (
            "status()'s coverage split no longer contains `%s` — this devtest's "
            "mirror has drifted from it and is asserting about dead code" % probe)
    return "mirror still matches status()'s split"


def t_a_timed_out_sha_is_not_covered():
    tested, incomplete = coverage([
        {"last": {"sha": "a" * 40, "verdict": "TIMEOUT", "timed_out": True}},
    ])
    assert "a" * 40 not in tested, (
        "a torn-down run must not silence the request for coverage")
    assert "a" * 40 in incomplete, "…but it must not vanish either"
    return "a timed-out sha lands in `incomplete`, not `tested`"


def t_a_complete_run_redeems_it_from_any_host_or_tier():
    """The timeout says THIS ATTEMPT was torn down, not that the sha is
    untestable. Another box finishing it is a complete answer."""
    tested, incomplete = coverage([
        {"host": "x", "last": {"sha": "a" * 40, "verdict": "TIMEOUT",
                               "timed_out": True}},
        {"host": "y", "history": [{"sha": "a" * 40, "verdict": "GREEN",
                                   "tier": "native"}]},
    ])
    assert "a" * 40 in tested, "a complete run anywhere redeems the sha"
    assert not incomplete, "and it must not be reported as incomplete too"
    return "a complete run on another host redeems a timed-out sha"


def t_a_legacy_record_reads_as_complete():
    """Migration order: entries written before the field existed carry no
    `timed_out`, and must keep counting. Same rule run_is_incomplete() uses --
    old states stay readable, they simply under-report."""
    tested, incomplete = coverage([
        {"history": [{"sha": "a" * 40, "verdict": "GREEN", "tier": "native"}]},
    ])
    assert "a" * 40 in tested and not incomplete
    return "a pre-field record still counts as tested"


def t_an_ordinary_red_still_counts_as_covered():
    """A RED is a complete answer. Only a torn-down run is not."""
    tested, _inc = coverage([
        {"last": {"sha": "a" * 40, "verdict": "RED", "timed_out": False}},
    ])
    assert "a" * 40 in tested, "a RED verdict is coverage; the run finished"
    return "RED counts as covered"


def t_history_entries_carry_the_field():
    src = open(os.path.join(HERE, "twatch.py")).read()
    seg = src.split('st["history"] = (st["history"] +', 1)[1][:900]
    assert '"timed_out": bool(report.get("timed_out"))' in seg, (
        "history entries no longer record timed_out, so staleness cannot tell "
        "a complete run from a torn-down one once st['last'] has moved past it")
    return "history records timed_out"


def main():
    rc = 0
    for fn in (t_the_mirror_matches_the_real_split,
               t_history_entries_carry_the_field,
               t_a_timed_out_sha_is_not_covered,
               t_a_complete_run_redeems_it_from_any_host_or_tier,
               t_a_legacy_record_reads_as_complete,
               t_an_ordinary_red_still_counts_as_covered):
        try:
            print("  ok   %s — %s" % (fn.__name__, fn()))
        except Exception as e:              # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s"
                  % (fn.__name__, type(e).__name__, fail_detail(e)))
    print("timeout staleness OK" if rc == 0 else "timeout staleness BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
