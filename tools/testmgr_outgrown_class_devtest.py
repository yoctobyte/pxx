#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest for the budget a job gets once it has OUTGROWN its class.

A job's class timeout is the budget for an UNMEASURED job. Once the job has its
own EWMA, Manager.__init__ tightens that budget to `exp_dur * 10 + 15` so a hang
is caught long before the coarse class figure would fire — a min() against the
class, deliberately one-directional.

The case that was unhandled is the measured duration itself passing the class
budget. The min() then hands the job a budget it cannot finish inside, and it is
killed at the ceiling on every run forever. learn_timeout() looks like the
rescue and is not: it raises the STORED duration "so the next run gets room",
and the same min() clamps that raise away on the next construction.

Measured 2026-08-19 on lib-test#src:test/crtl_exp2.c — EWMA 107.5s under a 90s
`unit` budget, RED in every full tier since 2026-08-17 while passing standalone
in 73.5s.

What must hold:

  * measured duration PAST the class budget -> budget is exp_dur * OUTGROWN_MARGIN,
    i.e. strictly more room than the job is known to need;
  * ...and it is ANNOUNCED by name — a silently inflated budget would hide the
    misclassification that caused it;
  * measured duration comfortably UNDER the class -> the tightened hang budget
    is unchanged (this must not become a licence to grow);
  * a job with too few samples to trust -> the plain class budget, unchanged;
  * learn_timeout()'s raise now survives into the next construction, which is
    what its docstring always claimed.

Constructs Managers directly against a stubbed metrics store: no jobs launched,
no repo state touched, nothing timing-dependent.
Run: python3 tools/testmgr_outgrown_class_devtest.py
"""
import argparse
import io
import contextlib
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import testmgr  # noqa: E402

FAILURES = []


def check(cond, msg):
    print("  %-4s %s" % ("ok" if cond else "FAIL", msg))
    if not cond:
        FAILURES.append(msg)


def build(metrics, cls="unit", scale=1.0, sel="test-core#src:test/x.pas"):
    """One Manager over one job, with `metrics` as the whole learned store.

    Returns (job, stdout-text) so a caller can assert on the budget AND on
    whether the run said anything about it.
    """
    job = testmgr.Job("test-core", 1, ["./pascal26 test/x.pas /tmp/x", "/tmp/x"])
    job.cls = cls
    job.sel = sel
    args = argparse.Namespace(tier="quick", serial=False, jobs=2, deadline=3600,
                              fail_fast=False, job=None, list=False)
    saved = testmgr.load_metrics
    testmgr.load_metrics = lambda: dict(metrics)
    buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(buf):
            testmgr.Manager([job], args, scale, "/tmp")
    finally:
        testmgr.load_metrics = saved
    return job, buf.getvalue()


def main():
    unit = testmgr.CLASSES["unit"]["timeout"]
    sel = "test-core#src:test/x.pas"
    rc = 0

    print("a job whose EWMA passed its class budget")
    # the real numbers from lib-test#src:test/crtl_exp2.c
    job, out = build({sel: {"dur": 107.54, "mem": 100149771, "cpu": 0.75, "n": 13}})
    check(job.timeout > job.exp_dur,
          "budget %.0fs exceeds the %.0fs it is known to need (was %.0fs)"
          % (job.timeout, job.exp_dur, unit))
    check(abs(job.timeout - 107.54 * testmgr.OUTGROWN_MARGIN) < 0.01,
          "budget is exp_dur * OUTGROWN_MARGIN = %.0fs" % job.timeout)
    check(sel in out and "outgrew" in out,
          "the raise is announced by job name, not applied silently")
    check("%.0f" % unit in out,
          "the announcement names the class budget it outgrew")

    print("a job still comfortably inside its class")
    job, out = build({sel: {"dur": 4.0, "mem": 1 << 20, "cpu": 1.0, "n": 13}})
    check(abs(job.timeout - max(45.0, 4.0 * 10 + 15, unit / 4)) < 0.01,
          "keeps the tightened hang budget, %.0fs" % job.timeout)
    check("outgrew" not in out, "says nothing — nothing outgrew anything")

    print("a job with too few samples to trust")
    job, out = build({sel: {"dur": 107.54, "mem": 1 << 20, "cpu": 1.0, "n": 1}})
    check(abs(job.timeout - unit) < 0.01,
          "plain class budget %.0fs — an untrusted EWMA raises nothing"
          % job.timeout)

    print("the same job on a box calibrated slower (scale 2)")
    job, out = build({sel: {"dur": 107.54, "mem": 1 << 20, "cpu": 1.0, "n": 13}},
                     scale=2.0)
    check(job.timeout > job.exp_dur,
          "scale applies to both sides: %.0fs budget over %.0fs expected"
          % (job.timeout, job.exp_dur))

    print("a bigger class is not dragged down by the same arithmetic")
    corpus = testmgr.CLASSES["corpus"]["timeout"]
    job, out = build({sel: {"dur": 300.0, "mem": 1 << 20, "cpu": 1.0, "n": 13}},
                     cls="corpus")
    check(abs(job.timeout - min(corpus, max(45.0, 300.0 * 10 + 15, corpus / 4))) < 0.01,
          "corpus job at 300s keeps its %.0fs class budget" % job.timeout)
    check("outgrew" not in out, "and is not announced")

    if FAILURES:
        print("\n%d check(s) FAILED" % len(FAILURES))
        rc = 1
    else:
        print("\nall checks passed")
    return rc


if __name__ == "__main__":
    sys.exit(main())
