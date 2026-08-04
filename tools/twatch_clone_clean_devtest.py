#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a bench that does NOT run must leave the clone byte-for-byte clean.

The incident this pins (2026-08-04): the bench quiet-gate incremented a
`bench_skips` counter and called `save_state()` on the skip path. `save_state`
writes `tstate/<host>.json`, which is TRACKED — so a skipped bench left the
clone dirty. The daemon's own dirty-clone guard then did exactly what it should
and paused every cycle, and the watcher sat wedged for **11 hours** over a
one-line `bench_skips: 0 -> 1` diff. Track T was down; dev boxes had no gate.

The rule this enforces: **anything written into the clone must ride a publish,
or not be written at all.** Operational counters are not published state and
belong in memory.

Uses a throwaway git repo shaped like a watcher clone; no daemon, no network.
Run: python3 tools/twatch_clone_clean_devtest.py
"""
import json
import pathlib
import subprocess
import sys
import tempfile
import types

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import twatch  # noqa: E402


def git(repo, *args):
    return subprocess.run(["git", "-C", str(repo), "-c", "user.name=t",
                           "-c", "user.email=t@t", "-c", "commit.gpgsign=false",
                           *args], capture_output=True, text=True)


def fake_clone():
    """A committed, clean repo with a host state file, like the real clone."""
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="clone-clean-"))
    (tmp / twatch.TSTATE_REL).mkdir(parents=True)
    (tmp / twatch.TSTATE_REL / "xeon.json").write_text(json.dumps({
        "host": "xeon", "last": {"sha": "a" * 40, "date": "2026-08-04T00:00:00Z",
                                 "verdict": "GREEN", "tier": "native"},
        "jobs": {}, "open_regressions": [], "history": [], "bench_skips": 0}))
    subprocess.run(["git", "init", "-q", str(tmp)], check=True)
    git(tmp, "add", "-A")
    git(tmp, "commit", "-qm", "seed")
    assert git(tmp, "status", "--porcelain").stdout == "", "fixture not clean"
    return types.SimpleNamespace(path=str(tmp))


def dirty(clone):
    return git(clone.path, "status", "--porcelain").stdout.strip()


def case_a_skipped_bench_leaves_no_trace():
    """The exact incident. A loaded box must skip and touch nothing."""
    clone = fake_clone()
    st = json.loads((pathlib.Path(clone.path) / twatch.TSTATE_REL
                     / "xeon.json").read_text())
    # Seed a very fast reference so any real probe reads as contended. NOT by
    # inflating speed_probe: on a fresh store the FIRST probe defines the
    # reference, so the ratio would be 1.00 no matter how slow it is.
    twatch._BENCH_RT.clear()
    twatch._BENCH_RT["xeon"] = {"skips": 0, "probe_ref": 1e-6}
    try:
        rc = twatch.run_bench_idle(clone, "xeon", st, "b" * 40)
    finally:
        twatch._BENCH_RT.clear()
    assert rc is False, f"a skipped bench should report no work done, got {rc!r}"
    assert not dirty(clone), (
        "a SKIPPED bench left the clone dirty — this is the 11-hour wedge:\n"
        + dirty(clone))
    return "loaded box -> skipped, clone untouched"


def case_counters_are_not_in_published_state():
    """Structural: the counters must not live in the tstate document at all,
    or some future path will persist them again."""
    src = pathlib.Path(twatch.__file__).read_text()
    for bad in ('st["bench_skips"]', 'st["bench_probe_ref"]',
                'st.get("bench_skips"', 'st.get("bench_probe_ref"'):
        assert bad not in src, f"bench counter is back in tstate: {bad}"
    assert "_BENCH_RT" in src, "the in-memory counter store is gone"
    return "counters live in memory, not in tstate"


def case_skip_counter_still_counts():
    """Moving them in-memory must not break the visibility they exist for."""
    clone = fake_clone()
    st = {"last_bench": {}}
    twatch._BENCH_RT.clear()
    twatch._BENCH_RT["xeon"] = {"skips": 0, "probe_ref": 1e-6}
    try:
        for _ in range(3):
            twatch.run_bench_idle(clone, "xeon", st, "c" * 40)
        n = twatch._BENCH_RT["xeon"]["skips"]
    finally:
        twatch._BENCH_RT.clear()
    assert n == 3, f"consecutive skips not counted: {n}"
    assert not dirty(clone), "still must not touch the clone"
    return "3 skips counted, clone still clean"


CASES = [
    case_a_skipped_bench_leaves_no_trace,
    case_counters_are_not_in_published_state,
    case_skip_counter_still_counts,
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
    print("clone-cleanliness OK" if rc == 0 else "clone-cleanliness BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
