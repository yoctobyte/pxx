#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a crashing run must not be localised to a statement it never reached.

`evaluate()` returns a SENTINEL for a run that crashed, timed out, or failed to
compile — one line, with the program's partial output discarded. That was fed
straight into a positional trace diff, so `min(len(la), len(lb))` was 1, the loop
compared index 0 only, always differed there, and the report read:

    first divergence at checkpoint 1 of 1 -- a `assign` statement
    (everything before it agrees, so the bug is AT that statement)

for a 27-checkpoint program that crashed somewhere else. Two falsehoods in one
paragraph: the statement named is the program's FIRST, not the guilty one, and
nothing was compared — so "everything before it agrees" is a claim about an empty
set, presented as evidence.

THE EXPENSIVE HALF IS THE DEDUP KEY. A signature is `<class>_<kind>`, so one
crashing bug split into as many signatures as its seeds had distinct first
statements. In the published ledger `fpc-self_assign`, `fpc-self_case` and
`fpc-self_forvarlimit` are three entries with three example-seed sets and three
recheck costs, all rc=217, all with byte-identical generator args, differing only
in seed. That is the "one bug wearing many names" failure the ledger exists to
remove, re-entering through the crash path — and the ledger cannot notice,
because from its side three names is three bugs.

The tell was visible in every one of those reports: `of 1` is
`min(len(la), len(lb))`, not the checkpoint count, so a truncated side prints
"of 1" for a 27-checkpoint program. A denominator that always equals its
numerator stops being read.

WHY THESE GUARDS ARE PURE. `diff_traces()` was extracted from `localize()`
precisely so this can be tested with strings — the old code could only be
exercised by compiling and running a program under two oracles, which is why the
defect survived. A test that needs a compiler is a test that does not run.

Run: tools/pasmith_localize_sentinel_devtest.py   (exit 0 = pass)
"""
import importlib.util
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
KINDS = ["assign", "case", "if", "for", "virtcall"]


def load():
    spec = importlib.util.spec_from_file_location(
        "pr_probe", os.path.join(HERE, "pasmith_run.py"))
    mod = importlib.util.module_from_spec(spec)
    argv = sys.argv
    sys.argv = ["pasmith_run.py"]
    try:
        spec.loader.exec_module(mod)
    except SystemExit:
        pass
    finally:
        sys.argv = argv
    return mod


pr = load()
TRACE = "111\n222\n333\n444"


def t_a_crash_is_not_localised_to_a_statement():
    """The regression, in its exact historical shape."""
    text, kind = pr.diff_traces(TRACE, "<crash>(rc=217)", "fpc-O0", "fpc-O2", KINDS)
    assert kind not in KINDS, (
        "a crashing run was localised to a `%s` statement -- that is the "
        "program's FIRST statement, not the guilty one, and the crash discarded "
        "the partial output so nothing was compared" % kind)
    assert kind == "crash-rc217", "expected the symptom as the kind, got %r" % kind
    assert "everything before it agrees" not in text, (
        "the report still claims the prefix agrees, which is a statement about "
        "an empty set:\n%s" % text)
    assert "UNKNOWN" in text, \
        "the report does not say the location is unknown:\n%s" % text
    return "crash -> crash-rc217, no statement named"


def t_the_crash_code_is_kept():
    """An unhandled exception and a segfault are different symptoms."""
    _, a = pr.diff_traces(TRACE, "<crash>(rc=217)", "x", "y", KINDS)
    _, b = pr.diff_traces(TRACE, "<crash>(rc=139)", "x", "y", KINDS)
    assert a != b, (
        "rc=217 (unhandled exception) and rc=139 (segfault) collapsed to one "
        "signature %r -- merging two symptoms is the same defect as splitting "
        "one, in the other direction" % a)
    return "%s vs %s stay distinct" % (a, b)


def t_timeout_and_compile_fail_get_their_own_kinds():
    for sentinel, want in ((pr.TIMEOUT, "timeout"),
                           (pr.COMPILE_FAIL, "compile-fail")):
        _, k = pr.diff_traces(TRACE, sentinel, "x", "y", KINDS)
        assert k == want, "%r localised as %r, wanted %r" % (sentinel, k, want)
    return "timeout and compile-fail named as themselves"


def t_a_sentinel_on_either_side_is_caught():
    """a_name is the larger group, so the sentinel can be on either side."""
    _, left = pr.diff_traces("<crash>(rc=217)", TRACE, "x", "y", KINDS)
    _, right = pr.diff_traces(TRACE, "<crash>(rc=217)", "x", "y", KINDS)
    assert left == right == "crash-rc217", \
        "a crash was only detected on one side: left=%r right=%r" % (left, right)
    return "either side"


def t_a_real_divergence_still_localises():
    """THE NEGATIVE CONTROL. A guard that only ever refuses is not a fix -- the
    working path is what the whole tool is for."""
    text, kind = pr.diff_traces("111\n222\n333", "111\n999\n333",
                                "pxx-O2", "pxx-O3", KINDS)
    assert kind == "case", \
        "the real localisation path broke: got %r, wanted kinds[1]='case'" % kind
    assert "checkpoint 2 of 3" in text, \
        "the checkpoint index or denominator is wrong:\n%s" % text
    assert "everything before it agrees" in text, \
        "the working path lost its explanation:\n%s" % text
    return "index 1 -> checkpoint 2 of 3, kind=case"


def t_identical_traces_are_not_a_divergence():
    _, kind = pr.diff_traces(TRACE, TRACE, "x", "y", KINDS)
    assert kind == "trace-length", \
        "two identical traces reported %r rather than trace-length" % kind
    return "identical -> trace-length"


def t_a_kind_past_the_end_does_not_raise():
    """Fewer recorded kinds than trace lines: a real case when --trace and the
    untraced build disagree about statement count."""
    _, kind = pr.diff_traces("1\n2\n3\n4\n5\n6", "1\n2\n3\n4\n5\n9",
                             "x", "y", ["assign"])
    assert kind == "?", "expected the unknown-kind marker, got %r" % kind
    return "missing kind -> '?'"


def t_sentinel_kind_says_None_for_a_real_trace():
    """The predicate must not claim a plain checksum is a symptom."""
    assert pr.sentinel_kind("16452949249337348755") is None, \
        "a real checksum was classified as a sentinel"
    assert pr.sentinel_kind(TRACE) is None, \
        "a multi-line trace was classified as a sentinel"
    return "a real trace is not a sentinel"


TESTS = [t_a_crash_is_not_localised_to_a_statement,
         t_the_crash_code_is_kept,
         t_timeout_and_compile_fail_get_their_own_kinds,
         t_a_sentinel_on_either_side_is_caught,
         t_a_real_divergence_still_localises,
         t_identical_traces_are_not_a_divergence,
         t_a_kind_past_the_end_does_not_raise,
         t_sentinel_kind_says_None_for_a_real_trace]


def main():
    bad = 0
    for t in TESTS:
        try:
            print("  ok   %-50s %s" % (t.__name__, t()))
        except Exception as e:  # noqa: BLE001
            bad += 1
            print("  FAIL %-50s %s" % (t.__name__, fail_detail(e)))
    print("  %d guard(s), %d red" % (len(TESTS), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
