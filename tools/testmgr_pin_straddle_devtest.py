#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a pin that moves mid-run must be detected and bounded.

testmgr already takes provenance seriously for the compiler it builds from
HEAD: snapshot it, record `compiler_sha256`, compare at the end, publish
INVALID when it moved -- because a run whose PASS/FAIL cannot be attributed to
one binary is not evidence. It did none of that for the PIN, which is what
lib-test actually builds with, and which is a SYMLINK that `make pin` moves.
That asymmetry was the bug: one binary guarded, the other merely announced.

Two properties, and the second is what keeps the fix from being worse than the
defect:

  * the pin is read at the START and again at the END, and a move is reported;
  * a move does NOT invalidate the run. The compiler snapshot invalidates
    everything because every job used it; the pin is used by 191 of the full
    tier's 3057 jobs. Discarding 3057 results because lib-test straddled a pin
    trades a small wrong claim for a large lost one.

And the detail that would have made the whole thing a no-op: `pin_straddled`
must name jobs by SELECTOR. twatch keys by job_key(), the stable
`lib-test#src:<file>` form; `lib-test#42` is a positional index that renumbers
when a recipe line is inserted. A list of names is a list twatch matches
nothing against -- a guard that runs and silently never fires.

Run: tools/testmgr_pin_straddle_devtest.py   (exit 0 = pass)
"""
import importlib.util
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tm", os.path.join(HERE, "testmgr.py"))
tm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tm)


def t_pin_identity_is_read_not_just_printed():
    assert hasattr(tm, "pin_identity"), (
        "pin_identity() is gone -- the pin can only be announced, not compared")
    got = tm.pin_identity()
    if got is None:
        return "SKIP - no pin in this checkout"
    ver, sha = got
    assert ver and sha, "pin identity must carry both version and sha256"
    return "pin identity readable: v%s %s" % (ver, sha)


def t_the_comparison_actually_distinguishes_two_pins():
    """Functional, not textual — and deliberately NOT by moving the real pin.

    The ticket is explicit: do not write a repro by pinning during a live run
    just to prove it. So drive `pin_identity()` over a stubbed `pin_file` and
    assert the tuple it returns really does differ across a pin move, which is
    the whole of what `pin0 != pin1` rests on. If this ever returns equal
    tuples for two different stables, the detection is a no-op however well the
    wiring reads.
    """
    orig = tm.pin_file
    seq = {"VERSION": ["374", "375"],
           "last.sha256": ["610bb9fa143074ef  pinned",
                           "5767e833aa0c115b  pinned"]}
    state = {"i": 0}

    def stub(name):
        return seq[name][state["i"]]
    tm.pin_file = stub
    try:
        before = tm.pin_identity()
        state["i"] = 1
        after = tm.pin_identity()
    finally:
        tm.pin_file = orig
    assert before != after, (
        "pin_identity() cannot tell v374 from v375 — `pin0 != pin1` is a no-op")
    assert before == ("374", "610bb9fa143074ef"), before
    assert after == ("375", "5767e833aa0c115b"), after
    # ...and it must NOT report a move when nothing moved.
    state["i"] = 1
    tm.pin_file = stub
    try:
        again = tm.pin_identity()
    finally:
        tm.pin_file = orig
    assert again == after, "a stable pin must compare equal across two reads"
    return "v374 vs v375 distinguished; an unmoved pin compares equal"


def t_the_pin_is_compared_at_the_end():
    src = open(os.path.join(HERE, "testmgr.py")).read()
    assert "pin1 = pin_identity() if pin0 else None" in src, (
        "the pin is no longer re-read at the end of the run, so a `make pin` "
        "landing mid-run is invisible again")
    assert "pin_changed_mid_run" in src, "the report no longer carries the field"
    return "read at start and end; reported as pin_changed_mid_run"


def t_a_moved_pin_does_not_invalidate_the_run():
    """The bound is the point. Without it this fix costs more than the bug."""
    src = open(os.path.join(HERE, "testmgr.py")).read()
    seg = src.split("pin_moved = bool(", 1)[1].split("if rc == 0", 1)[0]
    # CODE only. The first draft of this assertion matched the comment that
    # explains the rule -- "Deliberately NOT invalid=True" -- and went red on
    # the very prose describing the property it was checking. A text-shaped
    # guard reads prose as eagerly as code, which is the failure mode of every
    # text-shaped guard in this repo.
    code = "\n".join(ln for ln in seg.split("\n")
                     if not ln.strip().startswith("#"))
    assert "invalid = True" not in code and "invalid=True" not in code, (
        "a moved pin must NOT invalidate the whole run -- the pin is used by "
        "191 of the full tier's 3057 jobs, and discarding 3057 results because "
        "lib-test straddled a pin trades a small wrong claim for a large lost "
        "one")
    return "a moved pin marks the pin-built jobs, not the run"


def t_straddled_jobs_are_named_by_selector():
    """The detail that would have made the fix a silent no-op."""
    src = open(os.path.join(HERE, "testmgr.py")).read()
    assert "j.sel or j.name for j in jobs if j.pin_built" in src, (
        "pin_straddled must name jobs by SELECTOR: twatch keys by job_key(), "
        "and `lib-test#42` is a positional index it matches nothing against")
    tw_src = open(os.path.join(HERE, "twatch.py")).read()
    assert 'report.get("pin_straddled")' in tw_src, (
        "twatch no longer reads pin_straddled, so a straddled run files "
        "tickets against unattributable results")
    return "selector-keyed, and twatch consumes it"


def t_twatch_withholds_both_new_red_and_fixed():
    """FIXED is the easier half to forget, and the one nobody reports: a
    spurious NEW-RED sends someone looking, a spurious FIXED sends nobody."""
    tw_src = open(os.path.join(HERE, "twatch.py")).read()
    seg = tw_src.split('straddled = set(report.get("pin_straddled")', 1)[1][:1400]
    assert "new_red = [n for n in new_red if n not in straddled]" in seg, (
        "a straddled pin-built job must not open a ledger entry")
    assert "fixed = [n for n in fixed if n not in straddled]" in seg, (
        "…and must not publish a FIXED either -- same unattributable result, "
        "and the direction nobody checks")
    return "both directions withheld for straddled jobs"


def main():
    rc = 0
    for fn in (t_pin_identity_is_read_not_just_printed,
               t_the_pin_is_compared_at_the_end,
               t_the_comparison_actually_distinguishes_two_pins,
               t_a_moved_pin_does_not_invalidate_the_run,
               t_straddled_jobs_are_named_by_selector,
               t_twatch_withholds_both_new_red_and_fixed):
        try:
            print("  ok   %s — %s" % (fn.__name__, fn()))
        except Exception as e:              # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s"
                  % (fn.__name__, type(e).__name__, fail_detail(e)))
    print("pin straddle OK" if rc == 0 else "pin straddle BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
