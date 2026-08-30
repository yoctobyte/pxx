#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a job that has never passed on this box can earn room ONCE.

The trap this guards is a bootstrapping one. `learn_timeout()` records "it ran
at least this long" on every timeout so a job that got slower can escape a
stale-fast expectation -- but it deliberately leaves `n` at 0, and the only
consumer of that duration was gated on `n >= METRICS_MIN_RUNS`. So for a job
that has NEVER passed on this host the raise was written on every run and read
on none: it could only earn trust by passing, only pass with a bigger budget,
and only get a bigger budget by earning trust. Three jobs on `seven` sat there
permanently, entering new_red on every full tier and filing cascades against
commits they cannot have been caused by.

The n-gate is not an oversight, which is why this is delicate: it is what stops
a HANG from ratcheting its own budget (test_c_gtk_call.pas climbed 90s -> 2902s
-> 3522s off the unbounded path). Nothing in the stored data tells a slow box
from a hung job on a first encounter.

So the resolution is not to distinguish them. It is to BOUND the offer, which
makes the distinction stop mattering: one grant, then the class figure forever.
The slow job passes and starts earning real metrics; the hung job is killed at
the second budget, the grant is spent, and nothing grows. These guards are
therefore about the BOUND, not about the raise:

  * the raise happens at all, for a job with a duration and no trust;
  * it is refused once spent, and spent-ness survives in the metric;
  * the grant is counted when GRANTED, not when the timeout that prompted it
    was recorded -- otherwise the run that merely discovered the job was slow
    consumes the offer before anything is offered;
  * a job we already gave room to does NOT get its own budget recorded as its
    duration (that number is our guess, not the job's), which is what makes a
    single grant unable to compound;
  * a PASS returns the counter to full, so a job broken by a later commit gets
    the same one grant a new job gets;
  * a trusted job (n >= 2) is untouched -- the main path still owns it.

Run: tools/testmgr_unproven_budget_devtest.py   (exit 0 = pass)
"""
import importlib.util
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))


def load():
    spec = importlib.util.spec_from_file_location(
        "tm_probe", os.path.join(HERE, "testmgr.py"))
    mod = importlib.util.module_from_spec(spec)
    argv = sys.argv
    sys.argv = ["testmgr.py"]
    try:
        spec.loader.exec_module(mod)
    except SystemExit:
        pass
    finally:
        sys.argv = argv
    return mod


tm = load()


class FakeArgs:
    deadline = 3600.0


class FakeManager:
    """Just enough of Manager for learn()/learn_timeout(), which touch only
    self.metrics, self.args, self.scale and self.nproc."""
    def __init__(self, metrics=None):
        self.metrics = metrics or {}
        self.args = FakeArgs()
        self.scale = 1.0
        self.nproc = 8

    learn = tm.Manager.learn
    learn_timeout = tm.Manager.learn_timeout


def job(name="t#00", cls="qemu", dur=0.0, escalated=False):
    j = tm.Job("t", 0, ["echo hi"])
    j.name = name
    j.sel = name
    j.cls = cls
    j.t0 = 0.0
    j.t1 = dur
    j.escalated = escalated
    j.cpu_sec = 0.0
    j.peak_rss = 0
    return j


CLS = 240.0          # the `qemu` class budget, unscaled


def t_a_job_with_no_metric_gets_the_class_budget():
    """No observation yet means nothing to escalate FROM. Today's behaviour."""
    assert tm.unproven_budget(None, CLS) is None, \
        "a job with no metric was offered a raise, out of nothing"
    assert tm.unproven_budget({}, CLS) is None, \
        "an empty metric was treated as an observation"
    return "no metric -> class budget"


def t_an_observed_duration_earns_room():
    """The defect: this returned None for every job that had never passed."""
    got = tm.unproven_budget({"dur": 240.4, "n": 0}, CLS)
    assert got is not None, (
        "a job observed at 240.4s against a %.0fs budget was left on the class "
        "figure -- it can only earn trust by passing and can only pass with "
        "more room, which is the trap" % CLS)
    assert got == 240.4 * tm.OUTGROWN_MARGIN, \
        "expected the observed duration x OUTGROWN_MARGIN, got %r" % got
    return "observed 240.4s -> %.0fs budget" % got


def t_a_raise_that_would_not_help_is_not_taken():
    """Below the class figure the class figure is already the bigger number."""
    assert tm.unproven_budget({"dur": 3.0, "n": 0}, CLS) is None, \
        "a 3s job was 'raised' to 6s against a 240s budget, which is a cut"
    return "a raise below the class figure is declined"


def t_the_grant_is_spent_and_stays_spent():
    got = tm.unproven_budget({"dur": 240.4, "n": 0, "esc": 1}, CLS)
    assert got is None, (
        "a job that already had its one grant was offered another (%r) -- that "
        "is the ratchet the n-gate exists to prevent" % got)
    assert tm.unproven_budget({"dur": 9999.0, "n": 0, "esc": 5}, CLS) is None, \
        "a large stored duration bought its way past a spent grant"
    return "spent grant -> class budget, permanently"


def t_a_trusted_job_is_untouched():
    """n >= METRICS_MIN_RUNS belongs to the main path, which does more than
    set a timeout (exp_dur, exp_cores, est_mem)."""
    assert tm.unproven_budget({"dur": 240.4, "n": tm.METRICS_MIN_RUNS}, CLS) is None, \
        "the unproven path claimed a job the trusted path owns"
    return "n >= %d stays on the trusted path" % tm.METRICS_MIN_RUNS


def t_a_timeout_records_a_duration_but_no_grant():
    """The run that DISCOVERS the job is slow must not spend the offer."""
    mgr = FakeManager()
    mgr.learn_timeout(job(dur=240.0, escalated=False))
    m = mgr.metrics["t#00"]
    assert m["dur"] == 240.0, "the observed duration was not recorded: %r" % m
    assert int(m.get("esc") or 0) == 0, (
        "the grant was spent by the timeout that merely revealed the job is "
        "slow, before any extra room had been offered: %r" % m)
    assert tm.unproven_budget(m, CLS) is not None, \
        "after one honest timeout the job still cannot earn room"
    return "timeout records dur, leaves the grant unspent"


def t_a_timeout_at_a_granted_budget_spends_it_and_records_nothing():
    """Our own budget is not the job's duration -- recording it is the ratchet."""
    mgr = FakeManager({"t#00": {"dur": 240.0, "n": 0}})
    mgr.learn_timeout(job(dur=480.0, escalated=True))
    m = mgr.metrics["t#00"]
    assert int(m.get("esc") or 0) == 1, \
        "a timeout at a GRANTED budget did not spend the grant: %r" % m
    assert m["dur"] == 240.0, (
        "the granted budget (480s) was recorded as the job's duration -- next "
        "run would double THAT, which is how 90s became 3522s: %r" % m)
    assert tm.unproven_budget(m, CLS) is None, \
        "the job is still being offered room after its grant was spent"
    return "granted timeout: grant spent, our own budget not recorded"


def t_a_pass_returns_the_counter_to_full():
    """It counts CONSECUTIVE unproven timeouts, not lifetime ones."""
    mgr = FakeManager({"t#00": {"dur": 240.0, "mem": 1 << 20, "cpu": 1.0,
                                "n": 1, "esc": 1}})
    j = job(dur=100.0)
    j.peak_rss = 1 << 20
    mgr.learn(j)
    m = mgr.metrics["t#00"]
    assert "esc" not in m, (
        "a passing run left the escalation counter spent, so a job later "
        "broken by a commit is denied the grant a brand-new job gets: %r" % m)
    return "a pass clears the counter"


def t_the_bound_is_one_grant_end_to_end():
    """The whole lifecycle, because the guards above each see one step.

    A slow-box job and a hung job are INDISTINGUISHABLE here by construction --
    same class, same durations, same calls. The only difference is whether the
    escalated run passes. That is the point: the bound makes the distinction
    unnecessary."""
    mgr = FakeManager()
    budgets = []
    # run 1: no metric -> class budget -> timeout at it
    budgets.append(tm.unproven_budget(mgr.metrics.get("t#00"), CLS) or CLS)
    mgr.learn_timeout(job(dur=CLS, escalated=False))
    # run 2: the one grant -> timeout at the raised budget
    b2 = tm.unproven_budget(mgr.metrics["t#00"], CLS)
    budgets.append(b2 or CLS)
    mgr.learn_timeout(job(dur=b2, escalated=True))
    # runs 3 and 4: back to the class figure, and staying there
    for _ in range(2):
        b = tm.unproven_budget(mgr.metrics["t#00"], CLS)
        budgets.append(b or CLS)
        mgr.learn_timeout(job(dur=CLS, escalated=False))
    assert budgets == [CLS, CLS * 2, CLS, CLS], (
        "the budget sequence was %r; it must be one raise and then the class "
        "figure forever, or a hang ratchets" % budgets)
    assert max(budgets) <= CLS * tm.OUTGROWN_MARGIN, \
        "a budget exceeded one doubling: %r" % budgets
    return "class, 2x once, class, class"


TESTS = [t_a_job_with_no_metric_gets_the_class_budget,
         t_an_observed_duration_earns_room,
         t_a_raise_that_would_not_help_is_not_taken,
         t_the_grant_is_spent_and_stays_spent,
         t_a_trusted_job_is_untouched,
         t_a_timeout_records_a_duration_but_no_grant,
         t_a_timeout_at_a_granted_budget_spends_it_and_records_nothing,
         t_a_pass_returns_the_counter_to_full,
         t_the_bound_is_one_grant_end_to_end]


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
