#!/usr/bin/env python3
"""devtest: learned `mem` ratchets UP and decays DOWN — it is not an EWMA.

`dur` and `cpu` feed scheduling ORDER, where a mean is right. `mem` feeds
ADMISSION, where the two error directions cost opposite amounts: over-estimate
and the box packs fewer jobs than it could; under-estimate and it admits a job
on memory it does not have. A plain EWMA decays toward the mean, so a job whose
peak is occasional is admitted at its AVERAGE footprint and the run that
finally spikes meets a full box.

Measured 2026-08-27: three test-opt selfhost jobs each peaked at 521 MB against
a 500 MB class row, on a box carrying five workers.

Guards the asymmetry itself, not a particular constant.
"""
import os, sys, importlib.util

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tm", os.path.join(HERE, "testmgr.py"))
tm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tm)

fails = []
checks = 0


def check(cond, what):
    global checks
    checks += 1
    print(("  ok   " if cond else "  FAIL ") + what)
    if not cond:
        fails.append(what)


class FakeJob:
    """Minimal stand-in: learn() reads only these."""
    def __init__(self, peak, dur=10.0, cls="selfhost", name="j"):
        self.peak_rss = peak
        self.t0, self.t1 = 0.0, dur
        self.cpu_sec = dur
        self.cls = cls
        self.name = self.sel = name
        self.target = "test-opt"


class FakeSched:
    nproc = 12
    scale = 1.0
    def __init__(self):
        self.metrics = {}
    learn = tm.Manager.learn


def main():
    MB = 1 << 20
    s = FakeSched()
    j = FakeJob(500 * MB)
    key = tm.metrics_key(j)

    s.learn(j)
    check(s.metrics[key]["mem"] == 500 * MB, "first observation is learned as-is")

    # A SPIKE must be adopted immediately and in full — this is the whole point.
    s.learn(FakeJob(900 * MB))
    check(s.metrics[key]["mem"] == 900 * MB,
          "a spike ratchets straight to the observed peak, not partway")

    # A single lighter run must NOT drop the number to the mean, but it may
    # decay -- what it must never do is fall below what we just watched.
    before = s.metrics[key]["mem"]
    s.learn(FakeJob(500 * MB))
    after = s.metrics[key]["mem"]
    check(after < before, "a lighter run does decay the number (not a hard max)")
    check(after >= 500 * MB,
          "decay never lands below the run we just observed")

    # Sustained lighter running must converge downward, so a one-off spike
    # cannot inflate the row forever.
    for _ in range(25):
        s.learn(FakeJob(100 * MB))
    check(s.metrics[key]["mem"] <= 150 * MB,
          "sustained lighter runs converge back down")
    check(s.metrics[key]["mem"] >= 100 * MB,
          "convergence stops at the real footprint, never below it")

    # The contrast that justifies the asymmetry: dur stays a mean.
    s2 = FakeSched()
    s2.learn(FakeJob(100 * MB, dur=10.0))
    s2.learn(FakeJob(100 * MB, dur=100.0))
    k2 = tm.metrics_key(FakeJob(100 * MB))
    check(10.0 < s2.metrics[k2]["dur"] < 100.0,
          "dur is still an EWMA (a mean), unlike mem")

    # An unsampled run must fall back to the CLASS estimate, never to zero --
    # the regression the existing comment in learn() records.
    s3 = FakeSched()
    s3.learn(FakeJob(0))
    k3 = tm.metrics_key(FakeJob(0))
    check(s3.metrics[k3]["mem"] == tm.CLASSES["selfhost"]["est_mem"],
          "an unsampled run falls back to the class estimate, not 0")

    # The class row must cover what we have actually measured.
    check(tm.CLASSES["selfhost"]["est_mem"] >= 521 * MB,
          "the selfhost class row covers the 521 MB measured on 2026-08-27")

    print("\n%s (%d checks, %d failed)"
          % ("FAIL" if fails else "PASS", checks, len(fails)))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
