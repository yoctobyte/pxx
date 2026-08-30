#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: the fuzz ledger's THROTTLE REPORT must agree with the code that throttles.

The rate limiter has two halves that live in different files and do not import
each other:

  * the DECIDING half -- twatch.open_actionable_count(), which applies the
    backoff and already discounts NONACTIONABLE_CLASSES ("an external bug can
    never be resolved locally and would otherwise pin the fuzzer in permanent
    backoff");
  * the REPORTING half -- pasmith_run.ledger_status(), the line a human actually
    reads.

They disagreed. Measured 2026-08-30 against the published ledger: every
throttle-relevant entry was class `fpc-self`, so the deciding half computed 0
while the status line printed

    22 finding(s), 7 open. Fuzzing is throttled while any are open

Both halves of that sentence were false -- the 7 counted `ticketed` entries the
table on the SAME PAGE labelled `ticketed`, and nothing was throttled. It was
false in the direction that manufactures work: a reader triages five FPC
optimizer bugs to un-throttle a fuzzer that is already at full speed, and no pxx
commit can retire any of them.

WHY A CROSS-FILE GUARD AND NOT A SHARED IMPORT. Making twatch import the fuzz
runner couples a long-lived daemon to a one-shot tool for one frozen set; making
the runner import twatch is worse. So the constant is duplicated deliberately and
this file is what makes the duplication safe -- guard 1 fails the moment a class
is added on one side only, which is the only way they can drift.

WHAT IS DELIBERATELY NOT CHANGED: ledger_open() still includes the external
findings, because it is also the RECHECK population and fpc-self_trace-length was
marked fixed from exactly that path. "Can the fuzzer trip over it" and "does it
hold the fuzzer back" are different questions over the same table; the defect was
answering the second with the first.

Run: tools/pasmith_ledger_throttle_devtest.py   (exit 0 = pass)
"""
import ast
import importlib.util
import io
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
TWATCH = os.path.join(HERE, "twatch.py")
LIVE_LEDGER = os.path.join(REPO, "devdocs/progress/tstate/fuzz/LEDGER.json")


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


def twatch_constant():
    """Read twatch's set WITHOUT importing it -- it is a daemon, and executing it
    for one constant is how a devtest acquires side effects."""
    tree = ast.parse(io.open(TWATCH, encoding="utf-8").read())
    for node in tree.body:
        if isinstance(node, ast.Assign):
            for t in node.targets:
                if isinstance(t, ast.Name) and t.id == "NONACTIONABLE_CLASSES":
                    return set(ast.literal_eval(node.value))
    raise AssertionError(
        "twatch.py no longer defines NONACTIONABLE_CLASSES at module level -- the "
        "deciding half of the throttle moved or was renamed, and this guard can no "
        "longer check that the reporting half agrees with it")


def led(*entries):
    return {"findings": {e["sig"]: e for e in entries}}


def ent(sig, status, cls):
    return {"sig": sig, "status": status, "class": cls, "hits": 1, "ticket": None}


def status_text(ledger):
    out = io.StringIO()
    old = sys.stdout
    sys.stdout = out
    try:
        pr.ledger_status(ledger)
    finally:
        sys.stdout = old
    return out.getvalue()


def t_the_two_halves_name_the_same_classes():
    """The ONLY thing coupling the two files. Everything else here is downstream."""
    theirs, ours = twatch_constant(), pr.NONACTIONABLE_CLASSES
    assert theirs == ours, (
        "twatch.NONACTIONABLE_CLASSES=%r but pasmith_run.NONACTIONABLE_CLASSES=%r "
        "-- the half that DECIDES the backoff and the half that REPORTS it now "
        "disagree, so the status line is wrong for every class in the symmetric "
        "difference %r" % (sorted(theirs), sorted(ours),
                           sorted(theirs ^ ours)))
    return "both name %s" % "/".join(sorted(ours))


def t_an_external_finding_does_not_throttle():
    L = led(ent("fpc-self_if", "open", "fpc-self"))
    assert pr.ledger_throttling(L) == {}, \
        "an external (oracle) bug was counted as throttling the fuzzer"
    return "fpc-self open -> 0 throttling"


def t_an_ordinary_finding_still_throttles():
    """The negative control. A guard that only ever returns empty is not a guard."""
    L = led(ent("pxx-vs-fpc_case", "open", "pxx-vs-fpc"))
    assert set(pr.ledger_throttling(L)) == {"pxx-vs-fpc_case"}, \
        "a real pxx divergence stopped throttling -- the rate limiter is now off"
    L2 = led(ent("pxx-vs-fpc_case", "ticketed", "pxx-vs-fpc"))
    assert set(pr.ledger_throttling(L2)) == {"pxx-vs-fpc_case"}, (
        "a TICKETED pxx finding stopped throttling; filing a ticket does not stop "
        "the generator emitting the shape, which is the whole reason `dodged` is a "
        "separate status")
    return "pxx-vs-fpc open and ticketed both throttle"

def t_recheck_population_is_unchanged():
    """The externals must STAY in ledger_open: that is what recheck walks, and
    fpc-self_trace-length reached `fixed` through it."""
    L = led(ent("fpc-self_if", "open", "fpc-self"),
            ent("pxx-vs-fpc_case", "ticketed", "pxx-vs-fpc"),
            ent("pxx-vs-fpc_for", "fixed", "pxx-vs-fpc"))
    assert set(pr.ledger_open(L)) == {"fpc-self_if", "pxx-vs-fpc_case"}, (
        "the recheck population changed: %r. Excluding externals here would mean "
        "an FPC upgrade that retires one is never noticed."
        % sorted(pr.ledger_open(L)))
    return "recheck still walks externals; fixed excluded"


def t_the_summary_does_not_claim_a_throttle_that_is_not_there():
    """The literal regression, on the shape of the live ledger."""
    txt = status_text(led(ent("fpc-self_if", "open", "fpc-self"),
                          ent("fpc-self_for", "open", "fpc-self")))
    assert "FULL SPEED" in txt, \
        "nothing was throttling and the report did not say so:\n%s" % txt
    assert "is throttled while any are open" not in txt, (
        "the report still asserts the old unconditional claim:\n%s" % txt)
    return "0 throttling -> reported as full speed"


def t_the_summary_does_claim_one_when_there_is_one():
    txt = status_text(led(ent("pxx-vs-fpc_case", "open", "pxx-vs-fpc")))
    assert "THROTTLED by 1" in txt, \
        "a real throttle went unreported, which is the opposite failure:\n%s" % txt
    return "1 throttling -> reported as throttled"


def t_ticketed_is_not_counted_as_open():
    """The table and the summary printed different words for the same rows."""
    txt = status_text(led(ent("a", "open", "pxx-vs-fpc"),
                          ent("b", "ticketed", "pxx-vs-fpc"),
                          ent("c", "fixed", "pxx-vs-fpc")))
    assert "3 finding(s): 1 open, 1 ticketed." in txt, (
        "the summary miscounts the statuses the table above it prints:\n%s" % txt)
    return "1 open + 1 ticketed + 1 fixed counted separately"


def t_the_live_ledger_reports_honestly():
    """Against the real published file, not a fixture -- this is the number a
    human reads, and the fixture cannot notice a schema drift in the real one."""
    if not os.path.isfile(LIVE_LEDGER):
        return "skipped: no published ledger at %s" % os.path.relpath(LIVE_LEDGER, REPO)
    with io.open(LIVE_LEDGER, encoding="utf-8") as f:
        L = json.load(f)
    n = len(pr.ledger_throttling(L))
    txt = status_text(L)
    claims = "THROTTLED" in txt
    assert claims == bool(n), (
        "the published ledger has %d throttling finding(s) but the report %s a "
        "throttle:\n%s" % (n, "claims" if claims else "denies", txt))
    return "%d throttling, report agrees" % n


TESTS = [t_the_two_halves_name_the_same_classes,
         t_an_external_finding_does_not_throttle,
         t_an_ordinary_finding_still_throttles,
         t_recheck_population_is_unchanged,
         t_the_summary_does_not_claim_a_throttle_that_is_not_there,
         t_the_summary_does_claim_one_when_there_is_one,
         t_ticketed_is_not_counted_as_open,
         t_the_live_ledger_reports_honestly]


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
