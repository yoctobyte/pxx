#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a pin verify's NEW reds must carry their reasons.

`pin_verify.red` was a list of job NAMES. The reasons lived in `job_reason`,
which is the CURRENT red set from the newest run — set-or-clear, which is
correct behaviour and is exactly why it could not answer this question.

The two diverge precisely when it matters. Measured at the v367 verify
(`d47acfee770c`, 2026-08-19): 20 reds listed, `job_reason` held 9, and those 9
were the *inherited* reds still failing at HEAD. The 11 a reader actually had
to triage — the new ones, the ones a `make revert` fires on — were the 11 with
no reason recorded anywhere, because they were green again by the time the
newest run wrote the map. A peer spent six commands reconstructing by hand what
a stored reason answers in one look.

STORED RATHER THAN POINTED AT, and the guards below encode the bound that made
storing acceptable in a file every track fetches:

  * new reds only — a baseline red is not what anyone is triaging;
  * a per-entry character cap, so one pathological log cannot crowd out
    nineteen useful ones;
  * an entry-count cap that SAYS what it dropped;
  * no key at all when there is nothing to say, so the common case costs zero
    bytes.

Run: tools/twatch_pin_verify_why_devtest.py   (exit 0 = pass)
"""
import importlib.util
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location(
    "tw", os.path.join(HERE, "twatch.py"))
tw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tw)


def _report(pairs):
    """pairs: [(job_name, reason)] -> a report shaped like testmgr's."""
    return {"jobs": [{"target": n.split("#")[0], "name": n, "status": "fail",
                      "reason": r, "src": ""} for n, r in pairs]}


def _keys(pairs):
    return [tw.job_key(j) for j in _report(pairs)["jobs"]]


def t_a_new_red_carries_its_reason():
    rep = _report([("t#a", "assertion failed: 15 != 16")])
    why, new = tw.pin_verify_why(rep, set(), _keys([("t#a", "")]))
    assert len(new) == 1, new
    assert list(why.values()) == ["assertion failed: 15 != 16"], why
    return "a new red carries its reason"


def t_an_inherited_red_does_not():
    """A baseline red was failing before this pin; it is not the triage subject."""
    reds = _keys([("t#a", "")])
    rep = _report([("t#a", "was already broken")])
    why, new = tw.pin_verify_why(rep, set(reds), reds)
    assert new == [], "an inherited red was counted as new: %s" % new
    assert why == {}, "bytes were spent on an inherited red: %s" % why
    return "an inherited red spends no bytes"


def t_new_and_inherited_are_separated():
    """The mixed case is the real one — the v367 incident was 9 of 20."""
    reds = _keys([("t#old", ""), ("t#new", "")])
    rep = _report([("t#old", "inherited"), ("t#new", "the actual regression")])
    why, new = tw.pin_verify_why(rep, {reds[0]}, reds)
    assert len(new) == 1 and new[0] == reds[1], new
    assert list(why.values()) == ["the actual regression"], why
    return "a mixed set keeps only the new reds' reasons"


def t_a_reason_is_truncated_per_entry():
    """Per entry, not a shared budget: one bad log must not crowd out the rest."""
    long = "x" * 5000
    reds = _keys([("t#a", ""), ("t#b", "")])
    why, _ = tw.pin_verify_why(_report([("t#a", long), ("t#b", "short one")]),
                               set(), reds)
    assert len(why[reds[0]]) == tw.PIN_VERIFY_REASON_MAX, len(why[reds[0]])
    assert why[reds[1]] == "short one", \
        "a pathological entry crowded out a useful one: %r" % why[reds[1]]
    return "each reason is capped on its own"


def t_the_entry_count_is_capped():
    n = tw.PIN_VERIFY_REASON_CAP + 7
    pairs = [("t#%d" % i, "reason %d" % i) for i in range(n)]
    why, new = tw.pin_verify_why(_report(pairs), set(), _keys(pairs))
    assert len(new) == n, "the caller must still see the true count: %d" % len(new)
    assert len(why) == tw.PIN_VERIFY_REASON_CAP, len(why)
    return "the stored entry count is capped, the true count is not hidden"


def t_a_job_with_no_recovered_log_gets_no_entry():
    """Absence reads as 'not recorded'. An empty string reads as a CLAIM."""
    reds = _keys([("t#a", "")])
    why, _ = tw.pin_verify_why(_report([("t#a", "")]), set(), reds)
    assert why == {}, \
        "a job with no recovered log stored an empty reason, which reads as " \
        "'there was no reason': %s" % why
    return "no log means no entry, not an empty one"


def t_no_new_reds_costs_nothing():
    """The common case must not grow the shared file at all."""
    reds = _keys([("t#a", "")])
    why, new = tw.pin_verify_why(_report([("t#a", "r")]), set(reds), reds)
    assert why == {} and new == [], (why, new)
    return "a verify with no new reds stores no reasons"


def t_the_stated_bound_holds():
    """The ticket asked for the bound to be STATED and MEASURED, so measure it.

    Worst case is every entry at the cap, and it must stay small against the
    ~737 KB plexus.json that every track fetches.
    """
    import json
    n = tw.PIN_VERIFY_REASON_CAP
    pairs = [("t#%d" % i, "x" * 5000) for i in range(n)]
    why, _ = tw.pin_verify_why(_report(pairs), set(), _keys(pairs))
    size = len(json.dumps(why))
    ceiling = n * (tw.PIN_VERIFY_REASON_MAX + 40)     # + room for each key
    assert size <= ceiling, "worst case %d bytes exceeds the stated %d" % (size, ceiling)
    assert size < 8000, \
        "the worst case grew past 8 KB (%d) — restate the bound in the ticket " \
        "and in the constant's comment before raising a cap" % size
    return "worst case is %d bytes, under the stated bound" % size


def t_the_reason_field_is_read_not_the_job_name():
    """Guard against re-deriving the reason from anything but the report."""
    reds = _keys([("t#a", "")])
    why, _ = tw.pin_verify_why(_report([("t#a", "REAL-REASON")]), set(), reds)
    assert "REAL-REASON" in list(why.values())[0], why
    return "the stored text comes from the job's own reason field"


TESTS = [t_a_new_red_carries_its_reason,
         t_an_inherited_red_does_not,
         t_new_and_inherited_are_separated,
         t_a_reason_is_truncated_per_entry,
         t_the_entry_count_is_capped,
         t_a_job_with_no_recovered_log_gets_no_entry,
         t_no_new_reds_costs_nothing,
         t_the_stated_bound_holds,
         t_the_reason_field_is_read_not_the_job_name]


def main():
    rc = 0
    print("pin-verify-why devtest (%d guards)" % len(TESTS))
    for fn in TESTS:
        try:
            print("  ok   %s — %s" % (fn.__name__, fn()))
        except Exception as e:              # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s"
                  % (fn.__name__, type(e).__name__, fail_detail(e)))
    print("pin-verify-why OK" if rc == 0 else "pin-verify-why BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
