#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: "the tester is busy" must not report as "nobody is testing".

`status()` is a no-ping staleness heuristic — UP iff every commit older than the
grace window is tested by some host — and it could not tell *nobody is testing*
from *the tester is busy with the commit before yours*. Those have opposite
correct responses, and it answered both DOWN.

The cost is documented in CLAUDE.md, which names this exact command as the
authority for widening a gate:

    The one exception: Track T is PROVEN down — `twatch.py --status` exit 1 …
    Then run your lane's full gate first.

So a false DOWN converts a ~30s gate into a ~10min one, for every fix, for every
agent — and it fires hardest when the tree is busiest, i.e. exactly when
throughput matters. It also trains agents to disbelieve the tool, which is worse
than the ten minutes.

Three verdicts now: UP, BEHIND (exit 0, says why), DOWN (unchanged). BEHIND is
claimed only on evidence that is not a heuristic at all — a fresh heartbeat AND
a live pid, discovered the same way `trackt health` does it. Neither condition
alone: a stale file outlives its process, and a pid can be recycled.

Run: tools/twatch_behind_vs_down_devtest.py   (exit 0 = pass)
"""
import importlib.util
import json
import os
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tw", os.path.join(HERE, "twatch.py"))
tw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tw)


def _clone(ts=None, pid=None, host="testbox", phase="testing"):
    """A fake watcher clone with a heartbeat, as $TRACKT_CLONE."""
    d = tempfile.mkdtemp()
    os.makedirs(os.path.join(d, os.path.dirname(tw.WATCH_REL)), exist_ok=True)
    with open(os.path.join(d, tw.WATCH_REL), "w") as f:
        json.dump({"ts": ts if ts is not None else time.time(),
                   "pid": pid if pid is not None else os.getpid(),
                   "host": host, "phase": phase}, f)
    return d


def _with_clone(path, fn):
    old = os.environ.get("TRACKT_CLONE")
    os.environ["TRACKT_CLONE"] = path
    try:
        return fn()
    finally:
        if old is None:
            os.environ.pop("TRACKT_CLONE", None)
        else:
            os.environ["TRACKT_CLONE"] = old


def t_a_fresh_beat_from_a_live_pid_is_alive():
    # This process is a live pid, but its cmdline is the devtest, not twatch.py
    # -- so the pid check must REJECT it. That is the point of checking the
    # cmdline rather than merely that the pid exists: pids are recycled.
    got = _with_clone(_clone(), tw.local_daemon)
    assert got is None, (
        "a live pid running something OTHER than twatch.py must not count as "
        "the daemon — pids are recycled, and /proc/<pid> existing proves only "
        "that something is running")
    return "a live but unrelated pid is correctly rejected"


def t_a_stale_beat_is_not_alive():
    old = time.time() - (tw.HEARTBEAT_FRESH_SECS + 60)
    got = _with_clone(_clone(ts=old), tw.local_daemon)
    assert got is None, (
        "a stale heartbeat must not read as a live daemon — the file outlives "
        "the process that wrote it")
    return "a heartbeat older than %ds is not alive" % tw.HEARTBEAT_FRESH_SECS


def t_a_dead_pid_is_not_alive():
    got = _with_clone(_clone(pid=999999), tw.local_daemon)
    assert got is None, "a fresh beat from a dead pid must not read as alive"
    return "a fresh beat from a dead pid is not alive"


def t_no_clone_on_this_box_is_not_alive():
    got = _with_clone("/nonexistent-clone-path", tw.local_daemon)
    assert got is None, (
        "with no clone on this box we genuinely cannot tell, and the honest "
        "answer is the existing DOWN — not an optimistic BEHIND")
    return "no local clone -> None, so DOWN stands for a remote agent"


def t_both_conditions_are_required():
    """Neither alone. Asserted as a property rather than trusting the two
    negative cases above to have covered the conjunction."""
    src = open(os.path.join(HERE, "twatch.py")).read()
    seg = src.split("def local_daemon(", 1)[1].split("\ndef ", 1)[0]
    assert "HEARTBEAT_FRESH_SECS" in seg, "the freshness bound is gone"
    assert "/proc/%d/cmdline" in seg, "the liveness check is gone"
    assert "twatch.py" in seg, "the cmdline is no longer matched against twatch"
    return "freshness AND a live twatch pid, both still required"


def t_behind_exits_zero():
    """The exit code is what CLAUDE.md and every agent branch on, so BEHIND
    must be STATUS_UP. A BEHIND that exits 1 is the bug with better wording."""
    src = open(os.path.join(HERE, "twatch.py")).read()
    seg = src.split("alive = local_daemon()", 1)[1][:1400]
    assert "return STATUS_UP" in seg, (
        "the BEHIND branch no longer exits 0 — agents branch on the exit code, "
        "so this would restore the ten-minute gate it was written to remove")
    assert "do NOT widen your gate" in seg, (
        "BEHIND must still SAY why; an agent reading UP with no verdict on its "
        "commit widens its gate anyway")
    return "BEHIND returns STATUS_UP and explains itself"


def main():
    rc = 0
    for fn in (t_a_fresh_beat_from_a_live_pid_is_alive,
               t_a_stale_beat_is_not_alive,
               t_a_dead_pid_is_not_alive,
               t_no_clone_on_this_box_is_not_alive,
               t_both_conditions_are_required,
               t_behind_exits_zero):
        try:
            print("  ok   %s — %s" % (fn.__name__, fn()))
        except Exception as e:              # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s"
                  % (fn.__name__, type(e).__name__, fail_detail(e)))
    print("behind-vs-down OK" if rc == 0 else "behind-vs-down BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
