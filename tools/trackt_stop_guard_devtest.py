#!/usr/bin/env python3
"""devtest: `trackt stop` says what it is about to destroy, BEFORE the signal.

cmd_stop sent SIGTERM and then printed "aborting any running gate" -- after the
fact, and without naming what. A full pin verify is ~20 minutes on the artifact
every other lane builds against, and it is the hardest run to get, because it
needs a contiguous block the push rate rarely leaves.

Written after nearly throwing one away (2026-08-28). A scratch waiter tested
`phase != "testing"` and called `pin-verify` "safe to restart, nothing
discarded" -- a deny-list of the one busy state I happened to think of, so every
state I had not thought of defaulted to safe. GATE_PHASES is the allow-list that
was already correct and already in this file.

The second defect this guards is subtler and was live for one edit: the first
cut printed an age from watch.json's `ts`, which LOOKS like a phase-start stamp
and is a 30-second mid-run heartbeat. A 90-minute run printed as "running
0 min" -- wrong in the one direction that matters, since the line exists to say
how much is about to be lost. Duration must come from live.json.

So: what is checked here is not "does it print something" but the two ways the
line can lie -- a busy phase reported as idle, and a long run reported as short.
"""
import json, os, sys, tempfile, importlib.util

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
spec = importlib.util.spec_from_file_location("trackt", os.path.join(HERE, "trackt.py"))
tk = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tk)

fails = []
checks = 0


def check(cond, what):
    global checks
    checks += 1
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        fails.append(what)


def clone_with(watch=None, live=None):
    d = tempfile.mkdtemp(prefix="trackt-stopguard-")
    os.makedirs(os.path.join(d, ".testmgr"))
    if watch is not None:
        with open(os.path.join(d, ".testmgr", "watch.json"), "w") as f:
            json.dump(watch, f)
    if live is not None:
        with open(os.path.join(d, ".testmgr", "live.json"), "w") as f:
            json.dump(live, f)
    return d


print("== silence when nothing is at risk ==")
check(tk.describe_running("/nonexistent/clone") == "",
      "a clone that does not exist reports nothing")
check(tk.describe_running(clone_with()) == "",
      "no watch.json at all reports nothing")
check(tk.describe_running(clone_with(watch={"phase": "idle"})) == "",
      "phase=idle reports nothing")
check(tk.describe_running(clone_with(watch={"phase": "stopped"})) == "",
      "phase=stopped reports nothing")
check(tk.describe_running(clone_with(watch={})) == "",
      "watch.json with no phase key reports nothing")
d = clone_with()
open(os.path.join(d, ".testmgr", "watch.json"), "w").write("{not json")
check(tk.describe_running(d) == "", "corrupt watch.json reports nothing, does not raise")

print("== every GATE_PHASE is reported (allow-list, not deny-list) ==")
for ph in tk.GATE_PHASES:
    check(tk.describe_running(clone_with(watch={"phase": ph, "sha": "a" * 40})) != "",
          "phase=%s is reported as work at risk" % ph)
check("pin-verify" in tk.GATE_PHASES and "testing" in tk.GATE_PHASES,
      "GATE_PHASES still covers both testmgr-running phases")

print("== the line carries what a human needs to decide ==")
w = {"phase": "pin-verify", "sha": "83468c5462d4bb", "tier": "full", "pin": "v389",
     "ts": 1787872266.0}
live = {"done": 175, "total": 3202, "elapsed": 3000.0, "eta": 900.0}
line = tk.describe_running(clone_with(watch=w, live=live))
check("v389" in line, "names the pin")
check("full" in line, "names the tier")
check("83468c5462d4" in line, "names the sha")
check("175" in line and "3202" in line, "names the job progress")

print("== duration comes from live.json, never from watch.json's heartbeat ==")
# ts is refreshed every 30s mid-run, so now-ts is ~0 for a run of ANY length.
check("50 min" in line,
      "50 min of elapsed work is reported as 50 min (not as the heartbeat age)")
# NB the leading space: "50 min in" contains "0 min in", and the first cut of
# this very check asserted the substring and failed on a correct line. A test
# that cries wolf about the bug it guards is worse than no test.
check(", 0 min in" not in line,
      "a long run is never reported as '0 min in' (the heartbeat-age bug)")
stale = tk.describe_running(clone_with(watch=w, live=None))
check(stale != "" and "min" not in stale,
      "no live.json: still warns, but claims no duration rather than a wrong one")
d = clone_with(watch=w)
open(os.path.join(d, ".testmgr", "live.json"), "w").write("{broken")
check("min" not in tk.describe_running(d),
      "corrupt live.json degrades to the bare warning")
check("min left" not in tk.describe_running(clone_with(
          watch=w, live={"done": 1, "total": 2, "elapsed": 60.0, "eta": 0})),
      "eta of 0 is omitted rather than printed as '~0 min left'")

print("== cmd_stop warns BEFORE it signals ==")
src = open(os.path.join(HERE, "trackt.py")).read()
body = src[src.index("def cmd_stop("):]
body = body[:body.index("\ndef ", 1)]
check("describe_running" in body, "cmd_stop consults describe_running")
check(body.index("describe_running") < body.index("os.kill"),
      "the warning is emitted BEFORE os.kill, not after")
check("DISCARDS" in body, "the warning says the work is discarded, in plain words")

print("\n%d checks, %d failed" % (checks, len(fails)))
for f in fails:
    print("  FAIL " + f)
sys.exit(1 if fails else 0)
