#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: one hung job must not cost the run every other job's verdict.

The 2026-08-22..25 outage on plexus, in one sentence: a GTK test began hanging
when the box grew a desktop session, the harness recorded each kill as the
job's DURATION, the outgrown-class path doubled that into the next budget, and
within a day the budget (7045s) was larger than the run's own deadline (3600s)
— so every native tier spent its full hour on that one job and published a red
with nothing in it. 34 runs. Three days. No verdict for the fleet, while
`trackt health` said OK and the daemon genuinely was alive.

Four guards, and each fails silently without a test:

  * job_env() turns the a11y bridge off, because the hang was HOST COUPLING —
    the repo did not change, the box did. Same rule as stdin=DEVNULL: a job
    must not get a different answer depending on how the run was launched.
  * no budget may exceed MAX_JOB_DEADLINE_FRAC of the deadline. A budget past
    the deadline is not a budget; the job cannot pass, and the extra time buys
    only the loss of everything else. It dies as a TIMEOUT (a red with a
    reason) instead of as the global teardown (a red with nothing in it).
  * learn_timeout() must not record a duration at that ceiling — that figure
    is when the harness gave up, not how long the job takes. Recording it is
    what starts the ratchet.
  * a metric already latched must be DROPPED on load. A guard against future
    latching does not unlatch the 3522s already on record, and nothing else
    can: the job never passes, and only a pass calls learn().

Run: tools/testmgr_deadline_clamp_devtest.py   (exit 0 = pass)
"""
import importlib.util
import os
import sys
import tempfile
import types

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tm",
                                              os.path.join(HERE, "testmgr.py"))
tm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tm)

DEADLINE = 3600.0
CEILING = DEADLINE * tm.MAX_JOB_DEADLINE_FRAC      # 1800s


def fake_args(**kw):
    base = dict(serial=False, jobs=None, max_cores=0, deadline=DEADLINE,
                tier="native")
    base.update(kw)
    return types.SimpleNamespace(**base)


LINES = ["./compiler/pascal26 test/test_c_gtk_call.pas $(TESTTMP)/x",
         "xvfb-run -a $(TESTTMP)/x"]


def build(metric=None):
    """A Manager over one job, with `metric` already on record FOR THAT JOB.

    The key has to come from the job the Manager will actually schedule —
    metrics_key() derives it from the recipe, so a hand-written key silently
    misses and the scheduler reads an unmeasured job. That mistake made the
    clamp case pass for the wrong reason on first write.

    save_metrics is stubbed: heal_latched_metrics writes the cleaned file back,
    and a devtest must not touch the real .testmgr/metrics.json.
    """
    job = tm.Job("test-core", 0, list(LINES))
    job.sel = "test-core#src:test/test_c_gtk_call.pas"
    metrics = {tm.metrics_key(job): dict(metric)} if metric else {}
    saved = {}
    orig_load, orig_save = tm.load_metrics, tm.save_metrics
    tm.load_metrics = lambda: dict(metrics)
    tm.save_metrics = lambda m: saved.update({"m": dict(m)})
    try:
        mgr = tm.Manager([job], fake_args(), 1.0, tempfile.mkdtemp())
        return mgr, job, saved.get("m")
    finally:
        tm.load_metrics, tm.save_metrics = orig_load, orig_save


def key_for(job):
    return tm.metrics_key(job)


def t_job_env_kills_the_a11y_bridge():
    env = tm.job_env()
    assert env.get("NO_AT_BRIDGE") == "1", "NO_AT_BRIDGE not set: %r" % env.get("NO_AT_BRIDGE")
    # GTK4 ignores NO_AT_BRIDGE and honours this one. lib/pcl is an active
    # widgetset, so a move to GTK4 is a when, not an if.
    assert env.get("GTK_A11Y") == "none", "GTK_A11Y not set: %r" % env.get("GTK_A11Y")
    assert env.get("PATH") == os.environ.get("PATH"), "job env lost the real environment"
    return "NO_AT_BRIDGE=1 + GTK_A11Y=none, rest of the environment intact"


def t_latched_metric_is_dropped_on_load():
    """3522s on record against a 3600s deadline — the exact latch."""
    mgr, job, written = build({"dur": 3522.0, "cpu": 0.6, "mem": 1 << 27,
                               "n": 1635})
    k = key_for(job)
    assert k not in mgr.metrics, "latched metric survived load"
    assert written is not None and k not in written, \
        "cleaned metrics were not written back — it would re-latch next run"
    assert job.timeout <= CEILING, "budget %.0fs past the ceiling" % job.timeout
    return "dropped, persisted, and the job got a finite budget"


def t_healthy_metrics_are_untouched():
    good = {"dur": 7.0, "cpu": 0.9, "mem": 1 << 27, "n": 40}
    mgr, job, written = build(good)
    k = key_for(job)
    assert mgr.metrics.get(k) == good, "healed a healthy metric: %r" % mgr.metrics.get(k)
    assert written is None, "rewrote metrics.json when nothing needed healing"
    assert job.timeout < CEILING, "an ordinary 7s job got a ceiling-sized budget"
    return "a 7s job keeps its metric and its ordinary budget"


def t_outgrown_budget_is_clamped_to_the_deadline():
    """A legitimately slow job may outgrow its class — but not the run."""
    # 1200s measured: real, under the ceiling, so it is NOT healed away. The
    # outgrown path wants 1200*2 = 2400s, which the run cannot afford.
    mgr, job, _ = build({"dur": 1200.0, "cpu": 1.0, "mem": 1 << 27, "n": 30})
    assert key_for(job) in mgr.metrics, "healed a metric that was under the ceiling"
    assert job.timeout == CEILING, \
        "budget %.0fs — wanted the %.0fs clamp" % (job.timeout, CEILING)
    return "2400s raise clamped to %.0fs, metric kept" % CEILING


def t_learn_timeout_refuses_the_ceiling():
    mgr, job, _ = build()
    mgr.metrics = {}
    job.t0, job.t1 = 0.0, CEILING + 10          # killed at the clamp
    mgr.learn_timeout(job)
    assert mgr.metrics == {}, "recorded the harness's own ceiling as a duration"
    job.t0, job.t1 = 0.0, 120.0                 # an ordinary timeout
    mgr.learn_timeout(job)
    assert mgr.metrics, "refused to learn from an ordinary timeout too"
    assert abs(mgr.metrics[key_for(job)]["dur"] - 120.0) < 1.0
    return "ceiling refused, ordinary timeout still learned"


def main():
    rc = 0
    for fn in (t_job_env_kills_the_a11y_bridge,
               t_latched_metric_is_dropped_on_load,
               t_healthy_metrics_are_untouched,
               t_outgrown_budget_is_clamped_to_the_deadline,
               t_learn_timeout_refuses_the_ceiling):
        try:
            print("  ok   %s — %s" % (fn.__name__, fn()))
        except Exception as e:              # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s"
                  % (fn.__name__, type(e).__name__, fail_detail(e)))
    print("deadline clamp OK" if rc == 0 else "deadline clamp BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
