#!/usr/bin/env python3
"""devtest: --job-history answers the "is this red new?" question honestly.

Measured 2026-08-28, during the v389 pin verify. A second red appeared and I
asked the archive whether it had been seen before with a one-line scan for
`test-emit-obj`. It returned **0 hits in 1697 runs**, which reads as "brand
new" -- the single most consequential thing a triage can get wrong, because a
first-seen red is a revert candidate and an old one is a queue item.

The scan was correct and exhaustive and false. The archive keys on the STABLE
selector `test-emit-obj#src:test/cxtensa_obj.c@1`; `#02` is a positional index
into a Makefile recipe. The two strings share no substring, so there was no
near-miss to notice. A query against the wrong key returns zero and looks like
an answer.

The first draft of the fix was WORSE than the bug, and that is what most of
this file guards. `test-emit-obj#02` exists literally too -- from borg, 9 July,
opened and fixed inside 26 minutes -- so returning the literal match answered
the July history for a red opened yesterday: "2 runs, FIXED, a red now is a
REOPEN". A zero looks like an absence. A wrong history looks like research.

So the contract under test is: NEVER choose between two true histories, and
NEVER report an empty result without saying which kind of empty it is.
"""
import io, json, os, sys, contextlib, tempfile, importlib.util

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tw", os.path.join(HERE, "twatch.py"))
tw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tw)

fails = []
checks = 0


def check(cond, what):
    global checks
    checks += 1
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        fails.append(what)


def repo_with(runs, host="plexus", state=None):
    """A scratch repo holding an archive and (optionally) a state file."""
    d = tempfile.mkdtemp(prefix="twatch-jobhist-")
    ts = os.path.join(d, tw.TSTATE_REL)
    os.makedirs(ts, exist_ok=True)
    with open(os.path.join(ts, "runs-%s.ndjson" % host), "w") as f:
        for r in runs:
            f.write(json.dumps(r) + "\n")
    if state is not None:
        with open(os.path.join(ts, "%s.json" % host), "w") as f:
            json.dump(state, f)
    return d


def out_of(repo, name, host=None):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = tw.show_job_history(repo, name, host)
    return buf.getvalue(), rc


STABLE = "test-emit-obj#src:test/cxtensa_obj.c@1"
JULY = [
    {"date": "2026-07-09T06:03:47Z", "sha": "c" * 40, "tier": "full",
     "new_red": ["test-emit-obj#02"]},
    {"date": "2026-07-09T06:29:48Z", "sha": "b" * 40, "tier": "full",
     "fixed": ["test-emit-obj#02"]},
]
AUG = [
    {"date": "2026-08-27T09:35:00Z", "sha": "3" * 40, "tier": "full",
     "new_red": [STABLE]},
    {"date": "2026-08-27T21:28:16Z", "sha": "a" * 40, "tier": "full",
     "still_red": [STABLE]},
]
LEDGER = {"open_regressions": [{"name": "test-emit-obj#02", "job": STABLE}]}

print("== the original bug: a positional query must not return a false zero ==")
repo = repo_with(AUG, state=LEDGER)
txt, rc = out_of(repo, "test-emit-obj#02")
check(STABLE in txt, "a positional name resolves to the stable selector")
check("2 run(s)" in txt, "and reports the runs the stable selector has")
check(rc == 0, "exit 0 when a history was found")
check("POSITIONAL" in txt, "says out loud that the name given was positional")

print("== the first-draft bug: two true histories, never silently chosen ==")
repo = repo_with(JULY + AUG, state=LEDGER)
txt, rc = out_of(repo, "test-emit-obj#02")
check("2026-07-09" in txt, "the LITERAL July history is shown")
check("2026-08-27" in txt, "the STABLE August history is shown too")
check(txt.index("2026-07-09") < txt.index("2026-08-27"),
      "both are present, in run order, not one instead of the other")
check("different tests at different times" in txt,
      "warns that a recipe index means different tests at different times")

print("== the two kinds of empty are distinguishable ==")
txt, rc = out_of(repo_with(AUG), "no-such-target#99")
check(rc == 1, "a truly unknown job exits 1")
check("real absence" in txt and "vocabulary mismatch" in txt,
      "an unknown target says the absence is real, not a key mismatch")
txt, rc = out_of(repo_with(AUG), "test-emit-obj#77")
check("stable selector" in txt.lower() or STABLE in txt,
      "an unmatched INDEX on a known target offers that target's selectors")
check(rc != 0 or STABLE in txt,
      "and never silently reports 'nothing recorded' for a live target")

print("== transitions are read, not guessed ==")
txt, _ = out_of(repo_with(AUG, state=LEDGER), STABLE)
check("NOT new" in txt, "a job with a new_red row is reported as not new")
check("still open" in txt, "a run ending in still_red is reported as open")
txt, _ = out_of(repo_with(JULY), "test-emit-obj#02")
check("REOPEN" in txt, "a job whose last transition was FIXED reads as a reopen")

print("== degrades rather than raises ==")
d = repo_with(AUG)
with open(os.path.join(d, tw.TSTATE_REL, "runs-plexus.ndjson"), "a") as f:
    f.write("{not json\n")
txt, _ = out_of(d, STABLE)
check(STABLE in txt, "a corrupt archive line is skipped, the rest still reads")
txt, rc = out_of(tempfile.mkdtemp(prefix="twatch-empty-"), "anything#00")
check(rc == 1, "no archive at all exits 1 rather than raising")

print("== positional() knows what a recipe index looks like ==")
check(tw.positional("test-emit-obj#02"), "#02 is positional")
check(tw.positional("test-core#1532"), "#1532 is positional")
check(not tw.positional(STABLE), "a #src: selector is not positional")
check(not tw.positional("test-emit-obj"), "a bare target name is not positional")

print("\n%d checks, %d failed" % (checks, len(fails)))
for f in fails:
    print("  FAIL " + f)
sys.exit(1 if fails else 0)
