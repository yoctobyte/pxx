#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: the CPU budget that keeps a shared box usable.

plexus was a DEDICATED watcher box until 2026-08-20, when borg's PSU failed and
took the house down with it; plexus became the human's workstation the same day
and the watcher stopped being its only tenant. `--max-cores N` is the knob that
followed: N cores for the run, the rest for whoever is sitting at the machine.

Two mechanisms have to agree, and the failure mode of each is silent:

  * ADMISSION — the scheduler stops starting jobs once their learned core usage
    sums past the budget. It also has to drag the runaway guard (hard_cap) down
    with it: leaving hard_cap at nproc*2 while the budget says 6 means 24 job
    slots are still open and the throttle does nothing until admission catches
    up, one job at a time.
  * the cgroup CPUQuota on our own scope — the backstop for a job whose cost we
    mis-measured (one that forks its own `make -j`, say). Admission cannot see
    inside a job; the kernel can.

Invariants:

  * unset/0 means the whole box, byte for byte the old behaviour — no quota
    property, no changed cap. This is what every dedicated watcher still gets;
    a regression here throttles the fleet silently.
  * the budget never RAISES a ceiling: --max-cores 64 on a 12-core box is not
    a licence to oversubscribe, and it must not emit a CPUQuota above 100%.
  * hard_cap tracks the budget, keeping the 2x io-oversubscription ratio.
  * the quota and the weight both come out at the requested fraction, and the
    weight is lowered too — a quota alone still fights the human at equal
    weight for the half we did not reserve.

Run: tools/testmgr_cpu_budget_devtest.py   (exit 0 = pass)
"""
import importlib.util
import os
import sys
import types

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tm",
                                              os.path.join(HERE, "testmgr.py"))
tm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tm)


def props(budget, nproc):
    """scope_cpu_args as a dict: {'CPUQuota': '600%', ...}."""
    a = tm.scope_cpu_args(budget, nproc)
    assert all(a[i] == "-p" for i in range(0, len(a), 2)), \
        "malformed systemd-run properties: %r" % a
    return dict(kv.split("=", 1) for kv in a[1::2])


def cap_for(max_cores, nproc):
    """The hard_cap Manager would compute, without building one."""
    budget = tm.core_budget(max_cores, nproc)
    return (nproc * 2 if budget > nproc
            else max(2, int(round(budget * 2))))


def t_unset_is_the_whole_box():
    for unset in (0, None, "", 0.0):
        b = tm.core_budget(unset, 12)
        assert b == 13.0, "%r gave budget %r, not the historical nproc+1" % (unset, b)
        assert tm.scope_cpu_args(b, 12) == [], "%r pinned a quota" % (unset,)
        assert cap_for(unset, 12) == 24, "%r moved hard_cap off nproc*2" % (unset,)
    return "budget nproc+1, no quota, cap nproc*2 — unchanged"


def t_half_a_box():
    b = tm.core_budget(6, 12)
    assert b == 6.0, "budget %r" % b
    p = props(b, 12)
    # 600%, not 50%: systemd's CPUQuota is denominated in ONE cpu, so the
    # figure that LOOKS like "half the box" is half of a single core.
    assert p["CPUQuota"] == "600%", ("quota %s — six cores is 600%%, and 50%% "
                                     "would be half a core" % p["CPUQuota"])
    assert p["CPUWeight"] == "50", "weight %s" % p["CPUWeight"]
    assert cap_for(6, 12) == 12, "hard_cap %d, want the 2x ratio on 6" % cap_for(6, 12)
    return "6/12 -> CPUQuota=600%, CPUWeight=50, cap 12"


def t_never_raises():
    b = tm.core_budget(64, 12)
    assert b == 13.0, "clamp failed: %r" % b
    assert tm.scope_cpu_args(b, 12) == [], "emitted a quota above the box"
    assert cap_for(64, 12) == 24, "hard_cap %d" % cap_for(64, 12)
    return "over-budget clamped to the box, no quota"


def t_tiny_and_odd():
    assert tm.core_budget(0.1, 12) == 1.0, "sub-core budget not floored to 1"
    p = props(tm.core_budget(1, 12), 12)
    assert p["CPUQuota"] == "100%", "quota %s for one core" % p["CPUQuota"]
    assert int(p["CPUWeight"]) >= 10, "weight %s below systemd's floor" % p["CPUWeight"]
    assert tm.core_budget("nonsense", 12) == 13.0, "garbage did not fall back"
    assert tm.scope_cpu_args(tm.core_budget(0, 1), 1) == [], "1-core box throttled"
    return "floors, garbage and a 1-core box all sane"


def t_admission_stops_at_the_budget():
    """The gate that does the real work, exercised on a real Manager."""
    args = types.SimpleNamespace(serial=False, jobs=None, max_cores=6,
                                 deadline=3600)
    mgr = tm.Manager.__new__(tm.Manager)         # no job generation needed
    mgr.nproc = 12
    mgr.core_budget = tm.core_budget(args.max_cores, mgr.nproc)
    mgr.hard_cap = cap_for(args.max_cores, mgr.nproc)
    mgr.idle_frac = 1.0

    class J:
        def __init__(self, cores):
            self.exp_cores = cores
            self.resources = set()
            self.est_mem = 1 << 20
            self.t0 = 0.0
    mgr.running = [J(1.0) for _ in range(5)]
    now = 1e9
    assert mgr.admit_ok(J(1.0), now) is not False, \
        "refused the 6th core while the budget is 6"
    mgr.running.append(J(1.0))
    assert mgr.admit_ok(J(1.0), now) is False, \
        "admitted a 7th core against a 6-core budget"
    mgr.core_budget = tm.core_budget(0, mgr.nproc)
    assert mgr.admit_ok(J(1.0), now) is not False, \
        "an unthrottled run must still fill the box"
    return "admission holds at the budget, and only there"


def t_inner_timeouts_never_tighten():
    """A budget must not shorten scripts' inner per-item timeouts.

    The reason we budget cores is that somebody ELSE is on the box, and their
    load never appears in hard_cap — so the narrower run has to keep at least
    the patience the wide one had.
    """
    wide = tm.load_scale(24, tm.core_budget(0, 12), 12)
    assert wide == 2.0, "unthrottled scale changed: %r" % wide
    half = tm.load_scale(cap_for(6, 12), tm.core_budget(6, 12), 12)
    assert half >= wide, ("6/12 gave %r against %r wide — a throttled run got "
                          "LESS patience than a full-width one" % (half, wide))
    assert tm.load_scale(4, tm.core_budget(0, 12), 12) == 1.0, \
        "scale dipped below 1 (it may only ever extend a budget)"
    return "throttled runs keep full-width patience (%.2f)" % half


def main():
    rc = 0
    for fn in (t_unset_is_the_whole_box, t_half_a_box, t_never_raises,
               t_tiny_and_odd, t_admission_stops_at_the_budget,
               t_inner_timeouts_never_tighten):
        try:
            print("  ok   %s — %s" % (fn.__name__, fn()))
        except Exception as e:              # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s"
                  % (fn.__name__, type(e).__name__, fail_detail(e)))
    print("cpu budget OK" if rc == 0 else "cpu budget BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
