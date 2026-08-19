#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Guard: a cascade whose range straddles a pin says so, when it matters.

The case is real. In `regression-cascade-21f098e32a95` the `lib-test` job builds
with `$(PXX_STABLE)`, `cc20f7101` (pin v365) sat inside the 261-commit range,
and the failing test was ALREADY failing at the range's own last-good sha — the
pin merely caught up to a defect the source had carried for a while. Triage
found that by hand and left the conclusion as prose: *"any future cascade that
straddles a pin needs this question asked before the range is read."*

A note is a habit. This is the property:

  * the note appears only when BOTH halves hold — a pin moved inside the range
    AND at least one red job actually runs the pinned binary. Either alone is
    not a straddle, and a note that fires on one of them is noise that gets
    skimmed past on the day it is true;
  * it is a QUESTION with an experiment attached (build at last-good, run the
    job THERE), never a verdict — the watcher cannot know whether the defect
    predates the pin, and claiming it could is the same "we did not measure it,
    recorded as we measured it" substitution this harness keeps finding;
  * it names the affected jobs, because "some job here might be pin-built" sends
    the reader back through the whole list.

Run: python3 tools/twatch_pin_straddle_devtest.py
"""
import json
import os
import pathlib
import subprocess
import sys
import tempfile

TOOLS = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))
import twatch  # noqa: E402

fails = []
ran = []


def check(cond, what):
    ran.append(what)
    print("  %s %s" % ("ok  " if cond else "FAIL", what))
    if not cond:
        fails.append(what)


class FakeClone:
    def __init__(self, path):
        self.path = path
        self.branch = "master"


def git(d, *a):
    subprocess.run(("git",) + a, cwd=d, check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def commit(d, path, text, msg):
    f = pathlib.Path(d, path)
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_text(text)
    git(d, "add", "-A")
    git(d, "commit", "-qm", msg)
    return subprocess.run(["git", "rev-parse", "HEAD"], cwd=d, check=True,
                          capture_output=True, text=True).stdout.strip()


def build_repo(d):
    """good -> ordinary commit -> PIN commit -> ordinary commit -> bad."""
    git(d, "init", "-q", "-b", "master")
    git(d, "config", "user.email", "t@example.invalid")
    git(d, "config", "user.name", "t")
    good = commit(d, "compiler/a.pas", "1\n", "seed")
    c1 = commit(d, "compiler/a.pas", "2\n", "feat: something buildable")
    pin = commit(d, twatch.PIN_LOG_PATH,
                 "2026-08-19T00:00:00Z pinned v365 %s\n" % ("a" * 40),
                 "chore(stable): pin v365")
    c2 = commit(d, "lib/b.pas", "3\n", "feat: a library change")
    bad = commit(d, "devdocs/progress/x.md", "notes\n", "docs: tickets only")
    return {"good": good, "c1": c1, "pin": pin, "c2": c2, "bad": bad}


def note(clone, shas, pin_jobs, drop_pin=False):
    rng = [shas["c1"], shas["c2"], shas["bad"]] if drop_pin else \
          [shas["c1"], shas["pin"], shas["c2"], shas["bad"]]
    reg = {"good": shas["good"], "bad": shas["bad"], "range": rng,
           "job": "cascade@" + shas["bad"][:12]}
    return twatch.cascade_range_note(clone, reg, pin_jobs)


with tempfile.TemporaryDirectory(prefix="pin-straddle-") as d:
    shas = build_repo(d)
    clone = FakeClone(d)

    print("the pin inside the range is FOUND, and only the pin")
    reg = {"good": shas["good"], "bad": shas["bad"],
           "range": [shas["c1"], shas["pin"], shas["c2"], shas["bad"]]}
    found = twatch.pins_in_range(clone, reg)
    check(found == [shas["pin"]],
          "exactly the pin commit is identified (got %r)"
          % [c[:8] for c in found])
    # The range is what bounds the search, not good..bad. A pin OUTSIDE the
    # recorded range is not this cascade's straddle and must not be reported.
    check(twatch.pins_in_range(
        clone, dict(reg, range=[shas["c2"], shas["bad"]])) == [],
        "a pin outside the recorded range is not reported")
    check(twatch.pins_in_range(clone, {"good": None, "bad": None}) == [],
          "a regression with no range answers nothing rather than raising")

    print("BOTH halves are required — either alone is noise")
    both = note(clone, shas, ["lib-test#src:test/x.npy"])
    check("STRADDLES a pin" in both, "pin in range + a pin-built red -> the note")
    check("STRADDLES a pin" not in note(clone, shas, []),
          "a pin in range with NO pin-built red job -> no note")
    check("STRADDLES a pin" not in
          note(clone, shas, ["lib-test#src:test/x.npy"], drop_pin=True),
          "a pin-built red job with NO pin in range -> no note")

    print("...and it is a question with an experiment, not a verdict")
    # Assert on the STRADDLE PARAGRAPH, not the whole note. The range section
    # already prints the last-good sha, and the pin commit already appears in
    # its buildable listing (stable_linux_amd64/ is testable), so `in both`
    # would pass on text this feature did not write -- a true fact about the
    # wrong subject, in the guard for a feature about exactly that. Neutering
    # caught it: two checks stayed green with the note deleted.
    # Slice defensively: when the note is missing, every check below should
    # report as a NAMED failure, not as a traceback that buries which property
    # broke under a stack.
    i = both.find("STRADDLES a pin")
    para = both[i:] if i >= 0 else ""
    check(shas["pin"][:12] in para, "the straddle paragraph itself names the pin")
    check(shas["good"][:12] in para,
          "...and the last-good sha, which is where the experiment runs")
    check("exposed" in para and "caused" in para,
          "both readings are stated; the reader is not told which")
    check("lib-test#src:test/x.npy" in para,
          "the affected job is named, not left to be searched for")
    for word in ("is caused by", "was caused by", "not a regression"):
        check(word not in para, "it does not conclude (%r absent)" % word)

    print("the affected list is capped, and never silently")
    many = ["lib-test#src:test/j%02d.npy" % i for i in range(9)]
    big = note(clone, shas, many)
    check("+3 more" in big, "9 affected jobs -> 6 named and '+3 more' (got the count)")
    check(all(j in big for j in sorted(many)[:6]),
          "...and the six named are the first six by name, deterministically")

    print("the note is APPENDED — the range section keeps everything it had")
    check("Buildable commits in the range" in both and "last good" in both,
          "the existing range wording survives the addition")

print()
if fails:
    print("FAILED %d check(s):" % len(fails))
    for f in fails:
        print("  - " + f)
    sys.exit(1)
print("all %d pin-straddle guards green" % len(ran))
