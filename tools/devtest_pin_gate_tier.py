#!/usr/bin/env python3
"""Track T devtest: a pin does not escalate its gate on a stale local tstate.

bug-t-testmgr-pin-escalates-on-a-stale-local-tstate. `watcher_is_down()` reads
the LOCAL tstate/, which a dev checkout has stale most of the time — so the
rare-exception escalation fired on the common path and a pin ran >10 minutes
with the repo lock held while Track T was UP. Measured, then killed as a hang,
twice.

The property under test is a FAILURE DIRECTION, not a happy path: when the
evidence cannot be trusted, the answer must be "not down". Being wrong that way
costs a matrix sweep Track T does anyway; being wrong the other way costs every
lane minutes.
"""
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import testmgr as T                                            # noqa: E402

fails = []


def check(name, got, want):
    if got != want:
        fails.append("%s\n     got:  %r\n     want: %r" % (name, got, want))
    else:
        print("  ok  %s" % name)


# --- pin_gate_tier: the policy itself ---------------------------------------
check("default is quick when the watcher is up",
      T.pin_gate_tier(None, False), "quick")
check("escalates to limited only when PROVEN down",
      T.pin_gate_tier(None, True), "limited")
check("explicit --tier wins over an up watcher",
      T.pin_gate_tier("full", False), "full")
check("explicit --tier wins over a down watcher too — in BOTH directions",
      T.pin_gate_tier("quick", True), "quick")

# --- watcher_is_down: the EVIDENCE, which is what was broken -----------------
real_run = subprocess.run
calls = []


def fake_run(argv, **kw):
    calls.append(list(argv))

    class R:
        returncode = fake_run.rc.get(argv[0] if argv[0] != sys.executable
                                     else "twatch", 0)
    if fake_run.raise_on and fake_run.raise_on in argv[0]:
        raise OSError("simulated: git unavailable")
    return R()


def run_with(git_rc, twatch_rc, raise_on=None):
    calls.clear()
    fake_run.rc = {"git": git_rc, "twatch": twatch_rc}
    fake_run.raise_on = raise_on
    T.subprocess.run = fake_run
    try:
        return T.watcher_is_down()
    finally:
        T.subprocess.run = real_run


# a fetch happens BEFORE the status question — that is the whole fix
down = run_with(git_rc=0, twatch_rc=1)
check("fetches origin before asking", calls and calls[0][:2] == ["git", "fetch"], True)
check("watcher genuinely down -> down", down, True)
check("watcher up -> not down", run_with(git_rc=0, twatch_rc=0), False)

# the failure directions: a fetch that cannot run must NOT escalate
check("fetch fails (nonzero) -> treated as UP, no escalation",
      run_with(git_rc=1, twatch_rc=1), False)
check("fetch raises (offline / no git) -> treated as UP",
      run_with(git_rc=0, twatch_rc=1, raise_on="git"), False)

# and when the fetch fails we must not even ASK, since the answer would be
# about our own checkout rather than about Track T
run_with(git_rc=1, twatch_rc=1)
check("fetch failed -> does not consult the stale local tstate at all",
      any("twatch.py" in " ".join(c) for c in calls), False)

print()
if fails:
    print("FAIL (%d):" % len(fails))
    for f in fails:
        print("  - " + f)
    sys.exit(1)
print("devtest_pin_gate_tier: all checks pass")
