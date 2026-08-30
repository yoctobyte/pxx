#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: one green must not auto-close a stub whose failure is probabilistic.

The watcher retires a stub when its job goes green again. That is sound for a
deterministic test — build, run, compare, and a pass genuinely refutes the red —
and unsound for anything racy, where one green is what a LIVE bug produces most
of the time. It has already cost a real close:
`test-threads#src:test/test_sched_reactor_exhaustion.pas` was auto-closed twice
on 2026-08-29 while the defect was live, at a measured ~12% failure rate.

TWO PROPOSALS THAT DO NOT WORK, guarded here so they are not re-adopted:

  * "use RUN_RETRY_CLASSES." That set is {qemu, corpus, conformance, opt} and is
    about runtime variance from the ENVIRONMENT, not a test's own concurrency.
    classify() puts the reactor recipe in `unit` — so the class rule would not
    have caught the incident that produced the ticket. Kept as one arm because
    it is right about what it covers; it is not the arm that matters.
  * "require N consecutive greens." At ~12% failure, three greens still leave a
    68% chance the bug is live (0.88**3), and reaching 5% needs ~24. Absence is
    not evidence for a race at any affordable N.

What discriminates is evidence already in the record: the closing green was
itself FLAKY (the race fired while we watched), or the stub is a REPEAT variant
(`-2`, `-3` — stub_slug_for_filing opens those only when a resolved predecessor
exists, so the suffix IS the record that this job went red, was closed, and came
back). Neither needs new state.

Run: tools/twatch_autoclose_race_devtest.py   (exit 0 = pass)
"""
import importlib.util
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, path))
    mod = importlib.util.module_from_spec(spec)
    argv = sys.argv
    sys.argv = [path]
    try:
        spec.loader.exec_module(mod)
    except SystemExit:
        pass
    finally:
        sys.argv = argv
    return mod


tw = load("tw_probe", "twatch.py")
tm = load("tm_probe", "testmgr.py")


def rec(cls="unit", flaky=False):
    return {"name": "j#00", "sel": "j#00", "cls": cls, "flaky": flaky,
            "status": "pass", "src": "test/x.pas"}


def t_a_deterministic_first_stub_still_closes():
    """The rule must stay useful. 82 auto-closes have happened; a change that
    stops them all trades a silent wrong close for a silent backlog."""
    assert tw.one_green_cannot_close("regression-j", "regression-j",
                                     rec()) is None, \
        "a first-time green on a deterministic unit job no longer auto-closes"
    return "deterministic first stub closes as before"


def t_a_flaky_green_never_closes():
    why = tw.one_green_cannot_close("regression-j", "regression-j",
                                    rec(flaky=True))
    assert why, (
        "a green reached THROUGH A RETRY closed a ticket — the job failed and "
        "passed again in this same run, which is the race firing while we "
        "watched, not evidence against it")
    assert "retry" in why, "the reason does not say what was observed: %r" % why
    return "a flaky green is refused"


def t_a_repeat_stub_never_closes_on_one_green():
    """The arm that catches the reactor case."""
    why = tw.one_green_cannot_close("regression-j", "regression-j-2", rec())
    assert why, (
        "a REPEAT stub (`-2`) was closed on one green. The suffix exists only "
        "because a resolved predecessor did — the job went red, was closed, "
        "and came back, which is the definition of intermittent-or-unfixed")
    assert "repeat" in why.lower(), "the reason does not name the repeat: %r" % why
    assert tw.one_green_cannot_close("regression-j", "regression-j-7", rec()), \
        "only the -2 variant is treated as a repeat"
    return "repeat stubs are refused"


def t_the_retry_classes_arm_still_applies():
    for cls in sorted(tm.RUN_RETRY_CLASSES):
        assert tw.one_green_cannot_close("regression-j", "regression-j",
                                         rec(cls=cls)), \
            "a `%s` job closed on one green despite being a retry class" % cls
    return "all %d retry classes refused" % len(tm.RUN_RETRY_CLASSES)


def t_the_duplicated_class_set_has_not_drifted():
    """twatch does not import testmgr, so the copy is guarded instead."""
    assert tw.RETRY_CLASSES == tm.RUN_RETRY_CLASSES, (
        "twatch.RETRY_CLASSES %r has drifted from testmgr.RUN_RETRY_CLASSES "
        "%r — the copy exists because twatch does not import testmgr, and a "
        "silent divergence is what this guard is for"
        % (sorted(tw.RETRY_CLASSES), sorted(tm.RUN_RETRY_CLASSES)))
    return "the two class sets agree (%d)" % len(tw.RETRY_CLASSES)


def t_the_incident_is_covered_and_the_class_rule_alone_would_miss_it():
    """The reactor recipe classes `unit`, measured through classify().

    This is the guard that stops the ticket's own suggestion being re-adopted
    as sufficient: if someone deletes the repeat arm and keeps the class arm,
    this goes red with the reason."""
    recipe = ["./$(COMPILER) --threadsafe -dPXX_SCHED_TINY_REACTORS "
              "test/test_sched_reactor_exhaustion.pas "
              "$(TESTTMP)/test_sched_exhaust26",
              "$(TESTTMP)/test_sched_exhaust26"]
    cls = tm.classify(recipe)
    assert cls not in tm.RUN_RETRY_CLASSES, (
        "the reactor recipe now classes `%s`, which IS a retry class — this "
        "guard's premise has changed and its reasoning needs re-reading" % cls)
    assert tw.one_green_cannot_close("regression-t", "regression-t",
                                     rec(cls=cls)) is None, \
        "premise check failed: a first `%s` stub should close" % cls
    assert tw.one_green_cannot_close("regression-t", "regression-t-2",
                                     rec(cls=cls)), (
        "the reactor case is NOT covered: it classes `%s` (not a retry class), "
        "so only the repeat arm can catch it, and that arm is gone" % cls)
    return "reactor recipe classes `%s`; caught by the repeat arm, not the class arm" % cls


TESTS = [t_a_deterministic_first_stub_still_closes,
         t_a_flaky_green_never_closes,
         t_a_repeat_stub_never_closes_on_one_green,
         t_the_retry_classes_arm_still_applies,
         t_the_duplicated_class_set_has_not_drifted,
         t_the_incident_is_covered_and_the_class_rule_alone_would_miss_it]


def main():
    bad = 0
    for t in TESTS:
        try:
            print("  ok   %-56s %s" % (t.__name__, t()))
        except Exception as e:  # noqa: BLE001
            bad += 1
            print("  FAIL %-56s %s" % (t.__name__, fail_detail(e)))
    print("  %d guard(s), %d red" % (len(TESTS), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
