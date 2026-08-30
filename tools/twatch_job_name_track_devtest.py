#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a job whose NAME is a mechanism must be laned by the name.

Most job names describe what a job is ABOUT, so their lane depends on the
source — `test-core` runs the whole corpus across every lane, and laning it by
name would be a guess. A few name one machine-level mechanism, and then the lane
is a property of the NAME: `test-asm` IS the x86-64 text assembler/encoder, so
`test-asm#src:test/hello.pas` is Track A precisely BECAUSE hello.pas has nothing
to do with what is being tested.

THE MEASURED COST OF NOT HAVING THIS. Five p70 regressions were auto-filed as
`track: P` on 2026-08-30 (`regression-test-asm-*`), one reporting `undefined
variable (EmitSyscall)` in `compiler/x64enc.inc`. All five were the `test-asm`
job, none was frontend work, and all were invisible to the lane that owns the
file until a human re-laned them by hand.

AND THE FAILING-STEP FIX DID NOT COVER IT, which is why this is a second
mechanism rather than a bug in the first. Routing on the failing step lands on
the step's own sources — and those are `test/test_asm_emit_x64.pas` and
`test/test_x64enc.pas`, which `guess_track` answers `P` for, because
`TRACK_BY_SRC` ends in a `.pas` catch-all. Recording the step was necessary and
not sufficient: the step names the right file and the file still names the wrong
lane.

The second half of the fix is `("compiler/", "A")` in `TRACK_BY_SRC`, which is
correct independently: `compiler/compiler.pas` was routed to P by that same
catch-all, and the compiler's own source is not frontend work. It sits BEHIND
the frontends' carved-out files (`pasparser*`, `pylexer`, `cparser`, ...), which
also live under `compiler/` and are emphatically not A's — so the table's ORDER
is the correctness argument, and guard 5 is what holds it.

Run: tools/twatch_job_name_track_devtest.py   (exit 0 = pass)
"""
import importlib.util
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
LANES = set("ABCDNPRTZEOFSMUW")


def load(name, mod):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, mod))
    m = importlib.util.module_from_spec(spec)
    argv = sys.argv
    sys.argv = [mod]
    try:
        spec.loader.exec_module(m)
    except SystemExit:
        pass
    finally:
        sys.argv = argv
    return m


tw = load("tw_probe", "twatch.py")


def job(name, src, status="fail"):
    return {"job": "%s#src:%s" % (name, src), "name": name, "src": src,
            "status": status}


def t_the_five_historical_cases_all_lane_to_A():
    """The exact five, by their real selectors."""
    srcs = ["compiler/compiler.pas", "test/hello.pas",
            "test/test_asm_emit_x64.pas", "test/test_asmcore_x64.pas",
            "test/test_x64enc.pas"]
    bad = [s for s in srcs if tw.stub_track(job("test-asm", s))[0] != "A"]
    assert not bad, (
        "test-asm still lanes away from A for %r — these are the x86-64 "
        "emitter's own reds and the lane that owns the file cannot see them"
        % bad)
    return "5/5 test-asm sources -> A"


def t_the_source_is_ignored_for_a_mechanism_job():
    """The point of the table: the source is what the mechanism was RUN ON."""
    a = tw.stub_track(job("test-asm", "test/test_nilpy_thing.npy"))[0]
    assert a == "A", (
        "a .npy source pulled test-asm to %r — for a mechanism job the source "
        "is the input, not the subject" % a)
    return "even a .npy source leaves test-asm in A"


def t_a_subject_named_job_is_untouched():
    """THE NEGATIVE CONTROL. Laning every job by name is the failure this
    table must not become — `test-core` spans every lane."""
    got = tw.stub_track(job("test-core", "test/foo.pas"))[0]
    assert got == "P", \
        "test-core was laned as %r; it must still route from its source" % got
    got = tw.stub_track(job("test-core", "test/test_nilpy_x.npy"))[0]
    assert got == "N", "test-core with an .npy source lanes as %r" % got
    return "test-core still routes from the source"


def t_a_timeout_still_wins():
    """A timeout is a BUDGET fact. Nothing about a mechanism's name says its
    budget is that mechanism's fault, so the timeout arm stays ahead."""
    got, note = tw.stub_track(job("test-asm", "test/hello.pas", status="timeout"))
    assert got == "T", \
        "a timed-out test-asm was laned as %r, past the timeout arm" % got
    assert "TIMED OUT" in note, "the timeout hedge was lost: %r" % note[:80]
    return "timeout -> T, ahead of the name"


def t_the_frontend_carveouts_beat_the_compiler_sweep():
    """ORDER IS THE CORRECTNESS ARGUMENT. These files live under compiler/ and
    are not A's."""
    want = {"compiler/pasparser_expr.inc": "P", "compiler/pylexer.inc": "N",
            "compiler/pyparser.inc": "N", "compiler/cparser.inc": "C",
            "compiler/clexer.inc": "C", "compiler/cpreproc.inc": "C",
            "compiler/builtin/pylib.pas": "N"}
    bad = {p: tw.guess_track(p) for p, w in want.items()
           if tw.guess_track(p) != w}
    assert not bad, (
        "the `compiler/` sweep swallowed a frontend's own carved-out files: %r "
        "-- TRACK_BY_SRC is order-sensitive and must not be sorted" % bad)
    return "%d carve-out(s) survive the compiler/ entry" % len(want)


def t_compiler_sources_lane_to_A():
    for p in ("compiler/compiler.pas", "compiler/x64enc.inc",
              "compiler/ir_codegen.inc", "compiler/asmtext.inc"):
        got = tw.guess_track(p)
        assert got == "A", "%s lanes as %r, not A" % (p, got)
    return "compiler/** -> A"


def t_every_table_key_is_a_real_job():
    """A typo'd key is SILENTLY DEAD — it never matches, the table looks
    populated, and the routing it promises never happens."""
    tm = load("tm_probe", "testmgr.py")
    real = {t for tier in tm.TIERS.values() for t in tier}
    ghosts = sorted(set(tw.TRACK_BY_JOB) - real)
    assert not ghosts, (
        "TRACK_BY_JOB names %r, which no tier defines — a key that matches "
        "nothing is indistinguishable from coverage" % ghosts)
    return "%d key(s), all real jobs" % len(tw.TRACK_BY_JOB)


def t_every_table_value_is_a_lane_letter():
    bad = {k: v for k, v in tw.TRACK_BY_JOB.items() if v not in LANES}
    assert not bad, "TRACK_BY_JOB maps to non-lane letter(s): %r" % bad
    return "all values are lanes"


def t_the_note_says_where_the_lane_came_from():
    """A reader must be able to tell an override from a guess."""
    _, note = tw.stub_track(job("test-asm", "test/hello.pas"))
    assert "job NAME" in note, "the hedge does not say the name decided: %r" % note[:90]
    # The other arms open with "**Track guessed as X**". This one must not:
    # the table is evidence, not an inference. Checking that exact opener
    # rather than the bare word `guessed`, which the note legitimately uses in
    # a sentence explaining why guessing from the source would be wrong -- a
    # substring check called that a violation, which is the guard being cruder
    # than the property it is defending.
    assert "Track guessed as" not in note, (
        "the name table's hedge uses the GUESS opener, so a reader cannot tell "
        "an override from an inference: %r" % note[:110])
    return "the hedge names the source of the decision"


def t_job_family_strips_the_selector():
    assert tw.job_family({"job": "test-asm#src:test/hello.pas"}) == "test-asm"
    assert tw.job_family({"job": "test-core#665"}) == "test-core"
    assert tw.job_family({"name": "test-opt"}) == "test-opt"
    assert tw.job_family({}) == ""
    return "selector stripped, name fallback, empty is safe"


TESTS = [t_the_five_historical_cases_all_lane_to_A,
         t_the_source_is_ignored_for_a_mechanism_job,
         t_a_subject_named_job_is_untouched,
         t_a_timeout_still_wins,
         t_the_frontend_carveouts_beat_the_compiler_sweep,
         t_compiler_sources_lane_to_A,
         t_every_table_key_is_a_real_job,
         t_every_table_value_is_a_lane_letter,
         t_the_note_says_where_the_lane_came_from,
         t_job_family_strips_the_selector]


def main():
    bad = 0
    for t in TESTS:
        try:
            print("  ok   %-52s %s" % (t.__name__, t()))
        except Exception as e:  # noqa: BLE001
            bad += 1
            print("  FAIL %-52s %s" % (t.__name__, fail_detail(e)))
    print("  %d guard(s), %d red" % (len(TESTS), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
