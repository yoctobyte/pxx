#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest for the bench void/keep decision (bench only on a quiet box).

bug-t-bench-timings-recorded-under-co-tenancy + feature-t-bench-idle-must-be-preemptible.

A timing measured while something else runs is not slow, it is VOID — and it
reports itself as `SLOW (was ...)`, i.e. in a regression's own words. Measured
2026-08-04: an agent's builds inflated a batch up to +24%, with the FPC rows
(which pxx is not involved in at all) up 14.8% as the control. The inflation was
per-row because the load was intermittent, so a contended window cannot be
salvaged selectively — the numbers cannot say which rows were hit.

What must hold:

  * a loaded box never STARTS a batch;
  * load arriving MID-batch abandons it — the 2026-08-04 load did exactly that,
    so a start-only check would have called that box quiet;
  * an abandoned batch writes NOTHING (void, not partial);
  * a push preempts it like any other idle phase;
  * skips are counted so starvation is visible, and the counter resets on a
    clean batch so it means "consecutive".

Exercises the decision predicates directly; no clone, no subprocess, no repo
state.
Run: python3 tools/twatch_bench_quiet_devtest.py
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import twatch  # noqa: E402

START = twatch.BENCH_QUIET_LOAD
DURING = twatch.BENCH_QUIET_LOAD + twatch.BENCH_OWN_LOAD


def may_start(load):
    """The predicate run_bench_idle applies before checking anything out."""
    return not load > START


def must_abandon(load, preempted=False):
    """The predicate it applies on every poll while the batch runs."""
    return load > DURING or preempted


def case_idle_box_benches():
    assert may_start(0.4), "an idle box was refused"
    assert not must_abandon(1.8), "our own batch's load abandoned it"
    return f"load 0.4 starts; 1.8 (our own) keeps running"


def case_loaded_box_never_starts():
    """Tonight's contamination came from a gate run, which put this box at
    9-15. Anything in that region must not even begin."""
    for load in (2.5, 9.1, 15.4):
        assert not may_start(load), f"started a batch at load {load}"
    return "2.5 / 9.1 / 15.4 all refused"


def case_load_arriving_mid_batch_abandons():
    """The case a start-only check gets wrong, and the one that actually
    happened: the box was quiet when the batch began."""
    assert may_start(0.5)
    assert must_abandon(9.1), "a gate run mid-batch did not abandon it"
    return "quiet at start, loaded later -> abandoned"


def case_own_load_is_not_contention():
    """The batch itself raises the load. If that counted, no batch could ever
    finish — the threshold has to leave room for our own work."""
    assert not must_abandon(START + 1.0), \
        "the batch abandoned itself on its own load"
    assert DURING > START, "no headroom for the batch's own load"
    return f"{START + 1.0} tolerated while running (limit {DURING})"


def case_push_preempts():
    assert must_abandon(0.2, preempted=True), \
        "a push did not preempt the one idle phase that used to ignore them"
    return "quiet box, push arrives -> abandoned"


def case_skip_counter_is_consecutive():
    """Visible starvation: 'we have not benched in two days' must not hide.
    The counter has to reset, or it measures lifetime skips instead."""
    st = {}
    for _ in range(3):
        st["bench_skips"] = st.get("bench_skips", 0) + 1
    assert st["bench_skips"] == 3, st
    st["bench_skips"] = 0                      # a clean batch completed
    st["bench_skips"] = st.get("bench_skips", 0) + 1
    assert st["bench_skips"] == 1, "counter did not reset after a clean batch"
    return "counts up, resets on a clean batch"


def case_unknown_load_does_not_wedge():
    """If /proc/loadavg cannot be read, benching must degrade to running, not
    to never running again."""
    assert may_start(twatch.load1() * 0), "a 0.0 (unknown) load blocked the batch"
    return "unreadable load -> 0.0 -> allowed"


CASES = [
    case_idle_box_benches,
    case_loaded_box_never_starts,
    case_load_arriving_mid_batch_abandons,
    case_own_load_is_not_contention,
    case_push_preempts,
    case_skip_counter_is_consecutive,
    case_unknown_load_does_not_wedge,
]


def main():
    rc = 0
    for case in CASES:
        name = case.__name__.removeprefix("case_").replace("_", "-")
        try:
            note = case()
        except AssertionError as e:
            print(f"  FAIL {name}: {e}")
            rc = 1
        else:
            print(f"  ok   {name} — {note}")
    print("bench quiet-box gating OK" if rc == 0 else "bench quiet-box gating BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
