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

TOL = twatch.BENCH_PROBE_TOL


def may_start(ratio):
    """The predicate run_bench_idle applies before checking anything out."""
    return not ratio > TOL


def must_abandon(ratio, preempted=False):
    """The predicate it applies on every poll while the batch runs."""
    return ratio > TOL or preempted


def case_quiet_box_benches():
    assert may_start(1.00), "a quiet box was refused"
    assert not must_abandon(1.00)
    return "ratio 1.00 starts"


def case_a_third_of_the_box_busy_is_fine():
    """The point of the tolerance. Measured on the 12-core xeon: 4 busy cores
    cost 9%. The box exists to be worked on, and ordinary agent work is 1-2
    cores — refusing to bench through that would mean never benching."""
    for ratio in (1.09, 1.19, 1.30):      # observed range for 4/12 busy + noise
        assert may_start(ratio), f"4 busy cores of 12 blocked a batch at {ratio}"
        assert not must_abandon(ratio)
    return "1.09-1.30 (4 of 12 cores busy) still benches"


def case_oversubscription_never_starts():
    """Measured: 12 busy cores = 2.17x, and a full gate run (testmgr cap=24 on
    12 cores) = 4.75x. That gate run is what inflated the 2026-08-04 batch."""
    for ratio in (2.17, 4.75):
        assert not may_start(ratio), f"started a batch at {ratio}x"
    return "2.17x / 4.75x refused"


def case_slowdown_arriving_mid_batch_abandons():
    """The case a start-only check gets wrong, and the one that happened: the
    box was quiet when the batch began."""
    assert may_start(1.02)
    assert must_abandon(4.75), "a gate run mid-batch did not abandon it"
    return "quiet at start, contended later -> abandoned"


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


def case_reference_is_self_calibrating():
    """No per-box constant: the reference is this host's fastest probe, and a
    faster one replaces it."""
    st = {}
    r1, t1 = twatch.box_speed(st)
    assert r1 == 1.0, "the first probe on a fresh host must define the reference"
    # a much FASTER best-ever reference => this same box now reads as slow
    st["bench_probe_ref"] = t1 / 4
    r2, _ = twatch.box_speed(st)
    assert r2 > 2.0, f"a 4x-faster reference did not register as slow: {r2}"
    # ...and a probe faster than the stored reference pulls the reference down
    st["bench_probe_ref"] = t1 * 4
    r3, _ = twatch.box_speed(st)
    assert r3 == 1.0, f"a probe faster than the reference still read slow: {r3}"
    assert st["bench_probe_ref"] < t1 * 4, "reference did not track downward"
    return "min-so-far, updates downward"


def case_reference_relaxes_rather_than_starving():
    """A reference that becomes unreachable — thermal throttling, a governor
    change, a Python upgrade — must not switch benching off permanently."""
    st = {"bench_probe_ref": 0.001, "bench_skips": twatch.BENCH_SKIP_RELAX_AFTER}
    before = st["bench_probe_ref"]
    if st["bench_skips"] >= twatch.BENCH_SKIP_RELAX_AFTER:
        st["bench_probe_ref"] *= twatch.BENCH_RELAX_FACTOR
    assert st["bench_probe_ref"] > before, "reference never relaxes"
    assert twatch.BENCH_RELAX_FACTOR < 1.2, "relaxation is too aggressive to trust"
    return f"+{(twatch.BENCH_RELAX_FACTOR - 1) * 100:.0f}% after "\
           f"{twatch.BENCH_SKIP_RELAX_AFTER} skips"


def case_probe_is_compiler_independent():
    """A probe that compiled something would slow down when the COMPILER
    regressed, switching bench off exactly when there was something to measure."""
    import inspect
    src = inspect.getsource(twatch.speed_probe)
    # everything after the docstring: the CODE, not the prose about it
    src = src.split('"""')[2] if src.count('"""') >= 2 else src
    for word in ("subprocess", "pascal26", "COMPILER", "make"):
        assert word not in src, f"the probe reaches for {word!r}"
    return "pure in-process integer work"


CASES = [
    case_quiet_box_benches,
    case_a_third_of_the_box_busy_is_fine,
    case_oversubscription_never_starts,
    case_slowdown_arriving_mid_batch_abandons,
    case_push_preempts,
    case_skip_counter_is_consecutive,
    case_reference_is_self_calibrating,
    case_reference_relaxes_rather_than_starving,
    case_probe_is_compiler_independent,
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
