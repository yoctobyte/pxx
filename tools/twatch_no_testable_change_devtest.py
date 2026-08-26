#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: an empty blame range is EVIDENCE, not a missing bound.

A job passed at `good` and failed at `bad` with no testable commit in between.
Every commit in the interval touches only `devdocs/` or `docs/`, so the compiler
sources were identical and the self-host fixedpoint makes the binary identical
too. Same binary, same test, two verdicts — that is nondeterminism, by
construction, and no commit can be the cause because no commit is there.

twatch published it as a regression naming `ab584382edcd`: a 253-file commit
that edits nothing but `prio:` fields in ticket frontmatter. The range_note()
fallback explained the empty range as "first run covering this job at this
tier", which is false for a job with a recorded `good` — and whose real case
already had its own `first_seen` branch directly above. The correct sentence
existed one branch up, reachable only by pin-built jobs:

    the cause is in the box or the job's own inputs, not in the commits

Sixth instance in this family of *the right answer exists on a rare path and is
unreachable from the common one*.

Two properties this must never lose:

  * **the red still stands.** Only the ATTRIBUTION is impossible. Suppressing
    the failure would be a coverage hole; declining to name an innocent commit
    costs nothing.
  * **it must not fire when a range exists.** A pin-built job with 38 testable
    commits is the pin-axis case and keeps its own handling.

Run: tools/twatch_no_testable_change_devtest.py   (exit 0 = pass)
"""
import importlib.util
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tw", os.path.join(HERE, "twatch.py"))
tw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tw)

FAILS = []


def check(name, cond, detail=""):
    if cond:
        print("  ok   %s" % name)
    else:
        print("  RED  %s" % name)
        FAILS.append("%s\n      %s" % (name, detail))


def git(repo, *a):
    return subprocess.run(("git",) + a, cwd=repo, capture_output=True,
                          text=True, check=True).stdout.strip()


def build_repo():
    """A repo with: a code commit, then two devdocs-only commits."""
    d = tempfile.mkdtemp(prefix="ntc-devtest-")
    git(d, "init", "-q", "-b", "main")
    git(d, "config", "user.email", "t@example.invalid")
    git(d, "config", "user.name", "t")
    os.makedirs(os.path.join(d, "compiler"))
    os.makedirs(os.path.join(d, "devdocs", "progress"))

    def commit(path, text, msg):
        full = os.path.join(d, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        open(full, "a").write(text + "\n")
        git(d, "add", "-A")
        git(d, "commit", "-q", "-m", msg)
        return git(d, "rev-parse", "HEAD")

    # A root commit has no parent, so `git diff-tree --first-parent` prints
    # nothing and needs_test() answers False for it. Give the fixture a base so
    # every commit under test has a parent and the predicate is exercised for
    # real rather than through that edge.
    commit("README.md", "base", "base")
    code = commit("compiler/x.inc", "real change", "code")
    doc1 = commit("devdocs/progress/a.md", "prio: 40", "tickets: retriage")
    doc2 = commit("devdocs/progress/b.md", "prio: 55", "tickets: more retriage")
    return d, code, doc1, doc2


def main():
    print("twatch: an empty range is evidence, not a missing bound")
    repo, code, doc1, doc2 = build_repo()

    # --- the predicate the whole classification rests on -------------------
    check("needs_test says a devdocs-only commit is untestable",
          tw.needs_test(repo, doc2) is False,
          "if this is True the classification cannot work at all")
    check("needs_test says a compiler/ commit IS testable",
          tw.needs_test(repo, code) is True,
          "the guard must not simply answer False to everything")

    # Bypass __init__ deliberately: it clones, fetches and refuses to watch a
    # live dev checkout, none of which this exercises. The repair uses exactly
    # two members — `.path` and `.commits_between` — and those are what must be
    # real.
    clone = tw.Clone.__new__(tw.Clone)
    clone.path = repo

    # --- EXECUTE the interval computation the repair uses ------------------
    # Not a grep. The first draft of the repair called `commits_between(clone,
    # good, bad)` as a module function when it is a METHOD; that parses, greps
    # clean, and raises NameError only when an idle pass reaches it. The same
    # slip shipped once already this week (testable_only). So: call it.
    try:
        between = clone.commits_between(doc1, doc2)
        called = True
    except Exception as e:  # noqa: BLE001
        between, called = [], False
        check("clone.commits_between(good, bad) is callable as the repair calls it",
              False, "raised %r — the repair would die on an idle pass" % (e,))
    if called:
        check("clone.commits_between(good, bad) is callable as the repair calls it",
              True)
        testable = [c for c in between if tw.needs_test(repo, c)]
        check("doc1..doc2 contains commits but none testable",
              len(between) >= 1 and not testable,
              "between=%d testable=%d" % (len(between), len(testable)))

        acr = clone.commits_between(code, doc2)
        acr_t = [c for c in acr if tw.needs_test(repo, c)]
        check("a range spanning only devdocs is still empty when anchored lower",
              not acr_t, "testable=%s" % acr_t)

    # --- range_note(), which is what a human actually reads ----------------
    flake = {"job": "test-aarch64#src:test/x.pas", "bad": doc2, "good": doc1,
             "range": [], "no_testable_change": True, "pin_built": False,
             "first_seen": False, "bad_untestable": True}
    note = tw.range_note(flake)
    check("says nondeterminism", "nondeterminism" in note, note)
    check("does NOT claim this is the job's first run",
          "first run" not in note,
          "the old fallback asserted 'first run covering this job at this "
          "tier', which is false whenever `good` is recorded:\n%s" % note)
    check("promises no bisect", "No idle bisect will happen" in note, note)
    check("says the red itself still stands",
          "did fail" in note or "red itself stands" in note,
          "declining to attribute must not read as declining to report:\n%s" % note)
    check("points triage at load/timeouts, not at the diff",
          "not at the diff" in note, note)

    # --- it must NOT fire when there is something to bisect ----------------
    real = {"job": "test-core#src:test/y.pas", "bad": doc2, "good": code,
            "range": [code], "no_testable_change": False, "pin_built": False,
            "first_seen": False}
    note2 = tw.range_note(real)
    check("an ordinary regression keeps its bisect promise",
          "narrows this by idle bisect" in note2, note2)
    check("an ordinary regression is not called nondeterminism",
          "nondeterminism" not in note2, note2)

    # A pin-built job with observable commits stays on the pin axis.
    pin = {"job": "lib-test#src:test/z.npy", "bad": doc2, "good": code,
           "range": [code], "pin_axis": getattr(tw, "PIN_AXIS_RULE", 2),
           "pin_built": True, "first_seen": False, "no_testable_change": False}
    note3 = tw.range_note(pin)
    check("pin-built job keeps the pin-axis wording",
          "observable commit" in note3, note3)

    # first_seen wins over the empty-range branch: no `good` exists at all, so
    # "nothing changed between them" would be a claim about an interval that
    # does not exist.
    fs = {"job": "test-new#src:test/n.pas", "bad": doc2, "good": "",
          "range": [], "first_seen": True, "pin_built": False,
          "no_testable_change": False}
    note4 = tw.range_note(fs)
    check("a first-ever run is still reported as first-ever",
          "first-ever run" in note4, note4)

    # ---- the repair must not be behind a starved phase --------------------
    # It lived in bisect_step(), which is the LAST arm of an elif chain of idle
    # phases. On this box pin verify is preempted by pushes round after round,
    # so the chain never reached it: a dry run against the live state fired
    # THREE repairs at once that had never reached the published board, two of
    # them written hours earlier. A correction gated behind the busiest lock in
    # the system is the same defect it repairs — the right answer exists and the
    # common path cannot reach it.
    check("repair_regressions is a module-level function, not inlined in a phase",
          callable(getattr(tw, "repair_regressions", None)),
          "if this is gone the repairs are behind an idle slot again")

    st = {"open_regressions": [
        {"job": "test-x#src:test/x.pas", "bad": doc2, "good": doc1,
         "range": [doc2], "pin_built": False, "first_seen": False},
    ]}
    writes = []
    real_save = tw.save_state
    tw.save_state = lambda c, h, s: writes.append(1)
    try:
        tw.repair_regressions(clone, "h", st)
        reg = st["open_regressions"][0]
        check("repairing alone reclassifies — no bisect phase needed",
              reg.get("no_testable_change") is True, reg)
        check("...and drops the untestable commit from the range",
              not reg.get("range"), reg.get("range"))
        n1 = len(writes)
        tw.repair_regressions(clone, "h", st)
        check("a second pass is a no-op (idempotent, no rewrite storm)",
              len(writes) == n1,
              "wrote %d more time(s); a repair that always saves makes the "
              "clone dirty every cycle and wedges the publish loop"
              % (len(writes) - n1))

        # bisect_step must not rely on its caller having been polite.
        calls = []
        real = tw.repair_regressions
        tw.repair_regressions = lambda c, h, s: calls.append(1)
        try:
            tw.bisect_step(clone, "h", {"open_regressions": []}, "full")
        except Exception:
            pass          # it may bail for other reasons; we only care it called
        tw.repair_regressions = real
        check("bisect_step still repairs when reached directly", calls,
              "a repair that depends on another path having run is not a repair")
    finally:
        tw.save_state = real_save

    if FAILS:
        print("\ntwatch_no_testable_change_devtest: %d RED" % len(FAILS))
        for f in FAILS:
            print("  - %s" % f)
        return 1
    print("twatch_no_testable_change_devtest: all green")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:  # noqa: BLE001
        print(fail_detail(e))
        sys.exit(1)
