#!/usr/bin/env python3
"""A job that was KILLED is not a job that FAILED.

`teardown()` stops everything in flight -- on SIGINT, on the global deadline,
on a self-host red, on --fail-fast -- and used to mark each in-flight job
"fail". That was harmless while the only consumer was this process's exit code.
Two later consumers made it load-bearing, and both turn it into a phantom red:

  * the REPORT outlives the run, and the self-host-red / --fail-fast teardowns
    PUBLISH theirs. Every job that merely happened to be running alongside the
    real failure was published as a failure of its own, and twatch's merge
    (anything not PASSLIKE is red) files that fan-out as NEW-REDs.
  * the RESUME partial is that report persisted. `carried_red()` makes a
    carried "fail" gate the next slice by design, so a killed job would redden
    a run that never re-attempted it.

Measured 2026-08-20 on the live clone: `.testmgr/resume/ef3ea948003d-full.json`
held 14 "fail" and 1 "pass" from a full run aborted eight seconds in -- among
them `selfhost-fixedpoint#00` at 26.7s, the one red in this system that
triggers `make revert`.

Run: python3 tools/testmgr_interrupted_status_devtest.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import testmgr

ran, bad = [], []


def check(fn, what, why=""):
    ran.append(what)
    try:
        ok = fn()
    except Exception as e:                       # a guard that dies is a fail
        ok, why = False, "%s: %s" % (type(e).__name__, e)
    print("  %s %s" % ("ok  " if ok else "FAIL", what))
    if not ok:
        bad.append("%s%s" % (what, " -- " + why if why else ""))


class FakeProc:
    def wait(self, timeout=None):
        return 0


class FakeJob:
    """Only what teardown() and the report touch."""

    def __init__(self, name, status="running"):
        self.name = name
        self.sel = name
        self.cls = "unit"
        self.src = "test/%s.pas" % name
        self.status = status
        self.proc = FakeProc()
        self.t0 = 1.0
        self.t1 = None
        self.pin_built = False
        self.advisory = False
        self.flaky = False
        self.attempts = 1
        self.exp_dur = None
        self.timeout = 90
        self.lines = []
        self.logpath = None
        self.cpu_sec = 0.0
        self.peak_rss = 0
        self.deps = []


class FakeMgr:
    """A Manager stripped to the two methods under test. Not a real Manager:
    its constructor wants a parsed Makefile, and none of this is about recipes.
    """

    kill_group = staticmethod(lambda job: None)
    teardown = testmgr.Manager.teardown
    done_count = testmgr.Manager.done_count

    def __init__(self, jobs):
        self.jobs = jobs
        self.running = [j for j in jobs if j.status == "running"]


def torn_run():
    """A run with one real failure, two jobs killed alongside it, one queued."""
    jobs = [FakeJob("selfhost-fixedpoint#00"), FakeJob("test-nilpy#05"),
            FakeJob("test-core#00", status="fail"),
            FakeJob("test-c#00", status="queued")]
    mgr = FakeMgr(jobs)
    mgr.teardown()
    for j in jobs:
        if j.status == "queued":
            j.status = "skipped"
    return jobs


def main():
    print("a killed job is 'interrupted', never 'fail'")
    jobs = torn_run()
    by = {j.name: j.status for j in jobs}
    check(lambda: by["selfhost-fixedpoint#00"] == "interrupted",
          "teardown marks an in-flight job interrupted",
          "got %r -- a 'fail' here is the phantom revert trigger" % by)
    check(lambda: by["test-nilpy#05"] == "interrupted",
          "...every in-flight job, not just the first")
    check(lambda: by["test-core#00"] == "fail",
          "a job that really FAILED before the teardown keeps its verdict",
          "the fix must not launder a real red into 'interrupted'")
    check(lambda: by["test-c#00"] == "skipped",
          "a job that never launched stays 'skipped' (a different fact)")

    print("\nan interrupted job never reaches a consumer that would redden it")
    keep = testmgr.reportable(jobs)
    check(lambda: [j.name for j in keep] == ["test-core#00"],
          "the report carries the real failure and nothing else",
          "report jobs were %s" % [j.name for j in keep])
    check(lambda: "interrupted" in testmgr.NO_VERDICT,
          "...because 'interrupted' is in NO_VERDICT, beside queued/skipped")
    check(lambda: all(testmgr.report_job(j)["status"] != "interrupted"
                      for j in keep),
          "...so twatch's merge (not-PASSLIKE is red) never sees the status")
    red = [j.name for j in jobs if j.status in ("fail", "timeout")]
    check(lambda: red == ["test-core#00"],
          "the live `red` list names one job, not three")

    print("\nthe counters disagree on purpose: 'stopped' is not 'decided'")
    mgr = FakeMgr(jobs)
    dec, tot, _ = testmgr.live_progress(jobs)
    check(lambda: dec == 1 and tot == 4,
          "live_progress counts only the DECIDED job (1 of 4)",
          "got %d/%d -- counting a killed job as progress is the 2765/2765 bug"
          % (dec, tot))
    check(lambda: mgr.done_count() == 4,
          "done_count counts everything no longer RUNNING, torn jobs included",
          "got %d of 1 fail + 2 torn + 1 skipped" % mgr.done_count())

    print("\nload_resume's allow-list drops a status it never judged")
    import json
    import tempfile
    part = {"tier": "full", "compiler_sha256": "a" * 64,
            "jobs": [{"name": "a", "sel": "a", "status": "pass"},
                     {"name": "b", "sel": "b", "status": "fail"},
                     {"name": "c", "sel": "c", "status": "interrupted"}]}
    fd, path = tempfile.mkstemp(suffix=".json")
    with os.fdopen(fd, "w") as f:
        json.dump(part, f)
    try:
        carried, note = testmgr.load_resume(path, "full", "a" * 64)
    finally:
        os.unlink(path)
    names = [c["name"] for c in carried]
    check(lambda: names == ["a", "b"],
          "a hand-written 'interrupted' is refused even though 'fail' is kept",
          "carried %s -- the allow-list is what keeps carrying a real red safe"
          % names)
    check(lambda: testmgr.carried_red(carried),
          "(control) the carried real 'fail' still reddens the run")

    print("\n%d guard(s), %d failure(s)" % (len(ran), len(bad)))
    for b in bad:
        print("  FAIL %s" % b)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
