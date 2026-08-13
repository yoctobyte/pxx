#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: the pin's gate child inherits the lock instead of killing its holder.

bug-t-testmgr-pin-force-kills-its-own-parent. `--pin` holds the repo lock for
the WHOLE pin — deliberately, so no concurrent tier run rebuilds
compiler/pascal26 under stabilize-fast's feet — and then runs the gate as a
child of itself. The child called acquire_lock(force=True), found a live lock,
and killed its holder: its own parent. Exit 137, nothing pinned, 100% of the
time. `--force` was intended as "the lock you will find is mine, proceed anyway"
and was implemented as "kill whoever holds it".

Two kill paths, and fixing one alone leaves the command broken:

  * the --force path above, fixed by passing ownership DOWN (TESTMGR_LOCK_INHERITED);
  * the heartbeat reaper — the pin branch never started a heartbeat, so its lock
    went stale after 120s and ANY reader, its own child included, reaped it as
    wedged. A pin runs longer than that whenever the gate is not already green.

Run: tools/devtest_pin_lock_inherit.py   (exit 0 = pass)
"""
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tm", os.path.join(HERE,
                                                                "testmgr.py"))
tm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tm)


def held_by(pid, beat=None):
    """Write a lock file as if `pid` were mid-run."""
    now = time.time()
    tm.write_json_atomic(tm.LOCK_PATH, {
        "pid": pid, "tier": "pin", "started": now,
        "heartbeat": now if beat is None else beat})


def killed():
    """Everything kill_run() shot at, without shooting at it."""
    out = []
    tm.kill_run = lambda pid, why: out.append((pid, why))
    return out


def t_child_inherits(_root):
    """The load-bearing case: the gate child neither takes nor kills the lock."""
    parent = os.getppid()                   # a real, live, foreign-to-us pid
    held_by(parent)
    shots = killed()
    os.environ[tm.LOCK_INHERIT_ENV] = str(parent)
    try:
        assert tm.acquire_lock(True) is True, "child refused an inherited lock"
    finally:
        del os.environ[tm.LOCK_INHERIT_ENV]
    assert shots == [], "child shot at %r — the holder is its PARENT" % shots
    assert json.load(open(tm.LOCK_PATH))["pid"] == parent, "child stole the lock"
    return "lock left with pid %d, nothing killed" % parent


def t_child_does_not_release(_root):
    """It must not delete the parent's lock on the way out either.

    atexit-registered in every run, so this fires when the gate child exits —
    mid-pin, while stabilize-fast still needs the window the lock protects.
    """
    parent = os.getppid()
    held_by(parent)
    tm.release_lock()
    assert os.path.exists(tm.LOCK_PATH), "child released its parent's lock"
    return "lock survives the child's atexit"


def t_inherited_lock_vanished(_root):
    """Promised a lock that is gone: refuse, do not start killing for a parent
    that may itself be dead."""
    held_by(1)                              # someone else entirely
    shots = killed()
    os.environ[tm.LOCK_INHERIT_ENV] = str(os.getppid())
    try:
        assert tm.acquire_lock(True) is False, "took a lock it was not promised"
    finally:
        del os.environ[tm.LOCK_INHERIT_ENV]
    assert shots == [], "killed %r while cleaning up someone else's lock" % shots
    return "refused, killed nothing"

def t_pin_heartbeats(_root):
    """The second kill path: a pin whose lock never beats is reaped as wedged.

    Beat once and confirm the lock reads 'live', because that is what the
    reaper actually consults — asserting the thread exists proves nothing.
    """
    held_by(os.getpid(), beat=time.time() - 10 * tm.HEARTBEAT_STALE)
    assert tm.lock_state()[0] == "stale", "a lock this old should read stale"
    tm.start_heartbeat("pin")
    for _ in range(50):                     # the beat is threaded; give it a tick
        if tm.lock_state()[0] == "live":
            break
        time.sleep(0.02)
    state, info = tm.lock_state()
    assert state == "live", "pin lock still %s — reapable mid-pin" % state
    assert info["tier"] == "pin", info
    return "pin lock beats, so no reader reaps it"


def t_kill_run_spares_kin(_root):
    """Backstop, for whatever else learns to call kill_run()."""
    proc = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"])
    try:
        tm.kill_run(os.getpid(), "self")            # must be a no-op, obviously
        tm.kill_run(os.getppid(), "parent")
        assert tm.pid_alive(os.getppid()), "killed our own parent"
        tm.kill_run(proc.pid, "a stranger")         # a stranger is fair game
        proc.wait(timeout=10)
        assert proc.returncode != 0, "stranger survived: %r" % proc.returncode
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait(timeout=10)
    return "self and parent spared, unrelated run killed"


def main():
    rc = 0
    real_kill, real_lock = tm.kill_run, tm.LOCK_PATH
    for fn in (t_child_inherits, t_child_does_not_release,
               t_inherited_lock_vanished, t_pin_heartbeats,
               t_kill_run_spares_kin):
        root = tempfile.mkdtemp(prefix="devtest-pinlock-")
        tm.kill_run, tm.LOCK_PATH = real_kill, os.path.join(root, "run.lock")
        try:
            note = fn(root)
            print("  ok   %s — %s" % (fn.__name__, note))
        except Exception as e:            # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s" % (fn.__name__, type(e).__name__, e))
        finally:
            shutil.rmtree(root, ignore_errors=True)
    tm.kill_run, tm.LOCK_PATH = real_kill, real_lock
    print("pin lock inheritance OK" if rc == 0 else "pin lock inheritance BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
