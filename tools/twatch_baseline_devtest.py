#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest for autoticket suppression on unbaselined and infra-fault runs.

task-t-suppress-autoticket-until-host-baselined. `diff_jobs()` computes NEW-RED
as "red now, green in this host's recorded map". On a host's FIRST run that map
is empty and `prev_jobs.get(n, "pass")` defaults every unknown job to pass — so
every red is a NEW-RED, and with autoticket on the watcher files a cascade
ticket against whatever sha it happened to be testing.

xeon's enrollment did exactly that: 17 "newly red" jobs blamed on
110774a14648, a tstate-only commit that touches no code. All 17 were missing
host packages plus a stale seed; the ticket was rejected by hand.

Two guards, one rule — publish everything, file nothing you cannot stand behind:

  * no baseline yet -> the diff is against nothing;
  * more than INFRA_FAULT_FRAC of the matrix newly red -> an environment fault,
    since a commit that breaks a quarter of N unrelated subsystems at once
    essentially does not exist. This half pays off on a single host too, which
    is why it was built while the multi-host work is parked.

Pure functions only — no clone, no git, no repo state.
Run: python3 tools/twatch_baseline_devtest.py
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import twatch  # noqa: E402


def report_of(statuses):
    return {"jobs": [{"name": f"t#{i:03d}", "target": "test-core", "index": i,
                      "src": f"test/x{i}.pas", "status": s}
                     for i, s in enumerate(statuses)]}


def case_empty_baseline_makes_every_red_new():
    """The mechanism the guard exists for — documented, not assumed."""
    rep = report_of(["fail", "pass", "fail"])
    _now, new_red, _fixed, _still, _first = twatch.diff_jobs({}, rep)
    assert len(new_red) == 2, new_red
    return "2 reds against an empty map -> 2 NEW-RED"


def case_first_run_files_nothing():
    why = twatch.ticket_suppression(had_baseline=False, n_new_red=17, n_jobs=1098)
    assert why and "no baseline" in why, why
    return "unbaselined host -> suppressed"


def case_normal_regression_still_files():
    """The guards must not swallow the signal the watcher exists to produce."""
    assert twatch.ticket_suppression(True, 1, 1098) is None
    assert twatch.ticket_suppression(True, 9, 1098) is None
    return "1 and 9 of 1098 -> filed"


def case_matrix_wide_red_is_an_infra_fault():
    why = twatch.ticket_suppression(True, 300, 1000)
    assert why and "infra" in why, why
    assert "300 of 1000" in why, f"the reason must carry the numbers: {why}"
    return "300 of 1000 -> suppressed as infra"


def case_threshold_is_strict():
    """Exactly at the fraction still files: the claim is 'MORE than a quarter',
    and a boundary that suppresses would silently widen it."""
    n = 1000
    at = int(twatch.INFRA_FAULT_FRAC * n)
    assert twatch.ticket_suppression(True, at, n) is None, "at threshold: suppressed"
    assert twatch.ticket_suppression(True, at + 1, n) is not None, \
        "one past threshold: not suppressed"
    return f"boundary at {at}/{n}"


def case_no_reds_no_suppression():
    assert twatch.ticket_suppression(True, 0, 1098) is None
    return "green run -> nothing to suppress"


def case_tiny_matrix_does_not_divide_by_zero():
    """A --job run reports one job; the fraction must stay defined."""
    assert twatch.ticket_suppression(True, 0, 0) is None
    assert twatch.ticket_suppression(True, 1, 0) is not None
    return "n_jobs=0 handled"


CASES = [
    case_empty_baseline_makes_every_red_new,
    case_first_run_files_nothing,
    case_normal_regression_still_files,
    case_matrix_wide_red_is_an_infra_fault,
    case_threshold_is_strict,
    case_no_reds_no_suppression,
    case_tiny_matrix_does_not_divide_by_zero,
]


def main():
    rc = 0
    for case in CASES:
        name = case.__name__.removeprefix("case_").replace("_", "-")
        try:
            note = case()
        except AssertionError as e:
            print(f"  FAIL {name}: {e}")
            rc = 1
        else:
            print(f"  ok   {name} — {note}")
    print("autoticket suppression OK" if rc == 0 else "autoticket suppression BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
