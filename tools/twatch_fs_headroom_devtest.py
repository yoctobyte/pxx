#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: the breadth instrument can SEE a full filesystem, and stops filling one.

Two tickets, one job, and they only work together -- fixing the leak without the
guard means the next leak family is silent too, and adding the guard without the
reaper means a correct alarm nobody can act on:

  bug-t-devtest-and-twatch-helpers-leak-tmpdirs-until-tmp-runs-out-of-inodes
  bug-t-the-breadth-instrument-can-be-taken-down-by-a-full-disk-and-records-
      nothing-that-would-show-it

THE CONTROL THAT MATTERS IS NOT "THE FIELD IS PRESENT".

That passes on a host with a healthy disk, which is every host almost all of the
time, and it is the shape the guard ticket calls out by name. The controls here
are drawn from the population the question is about: seven's ACTUAL numbers at
the moment of the 2026-09-07 outage --

    $ df -h /tmp                          $ df -i /tmp
    tmpfs  47G  4.1G  43G   9% /tmp       tmpfs  1048576  1048568  8  100% /tmp

-- 8 free inodes with the filesystem 9% full. Every case below that asserts the
new reading FIRES also asserts that a BYTES-ONLY reading of the same filesystem
DOES NOT. Without that second half the suite would pass just as happily on a
guard built from shutil.disk_usage, which is the guard that cannot fail.

Run: tools/twatch_fs_headroom_devtest.py   (exit 0 = pass)
"""
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)

import fsheadroom  # noqa: E402

# seven, 2026-09-07, at the moment testmgr could not create its scratch dir.
OUTAGE = {"bytes_free": 43 * 1024**3, "bytes_total": 47 * 1024**3,
          "inodes_free": 8, "inodes_total": 1048576}
# The same box a day after remediation: still fine, and the number that matters
# is already 34% consumed while bytes read 5%.
HEALTHY = {"bytes_free": 44 * 1024**3, "bytes_total": 47 * 1024**3,
           "inodes_free": 699265, "inodes_total": 1048576}
# btrfs / ZFS / some overlays: inodes are allocated dynamically and statvfs
# reports zeros. Naively that is "0 free of 0" -- 100% exhausted, forever.
UNLIMITED = {"bytes_free": 80 * 1024**3, "bytes_total": 94 * 1024**3,
             "inodes_free": None, "inodes_total": None}


def bytes_only_would_pass(h):
    """What the guard that was NOT written would have said.

    shutil.disk_usage / f_bavail, i.e. every disk check anybody reaches for
    first. Returns True when it sees nothing wrong -- so asserting this is True
    on the outage numbers is asserting that the obvious guard is blind.
    """
    return h["bytes_free"] > 4 * 1024**3


def case_the_outage_is_detected_and_bytes_alone_miss_it():
    why = fsheadroom.low(OUTAGE)
    assert why, "the 2026-09-07 outage numbers did not trip the guard"
    assert "inode" in why, "the reason does not name inodes: %r" % why
    # The half that makes this a control rather than a demonstration.
    assert bytes_only_would_pass(OUTAGE), (
        "the bytes-only reading ALSO failed on these numbers, so this case "
        "cannot show that inodes are what discriminates -- pick numbers where "
        "bytes really are healthy")
    n, which = fsheadroom.runs_left(OUTAGE)
    assert n == 0 and which == "inodes", (n, which)


def case_a_healthy_box_does_not_cry_wolf():
    """The mirror control. An alarm that fires on a fine box gets ignored, and
    then it is not there on the day it is right."""
    assert fsheadroom.low(HEALTHY) is None, fsheadroom.low(HEALTHY)
    n, which = fsheadroom.runs_left(HEALTHY)
    assert n >= fsheadroom.MIN_RUNS, (n, which)
    # ...and it is still inode-bound at 34% consumed, which is the tell the
    # producer ticket's second reading recorded a day after remediation.
    assert which == "inodes", which


def case_no_inode_limit_is_not_no_inodes_left():
    assert fsheadroom.low(UNLIMITED) is None, (
        "a filesystem that reports f_files=0 was read as exhausted; that is a "
        "permanent false alarm on btrfs/ZFS, and a field that cries wolf gets "
        "learned around before the day it is right")
    n, which = fsheadroom.runs_left(UNLIMITED)
    assert which == "bytes", which


def case_probe_and_row_agree_and_null_is_explicit():
    row = fsheadroom.row("/tmp")
    for k in ("fs_bytes_free_mb", "fs_bytes_total_mb",
              "fs_inodes_free", "fs_inodes_total"):
        assert k in row, "missing %s" % k
    # A path that cannot be statvfs'd must yield present-and-null, never absent:
    # an absent key reads as "this version did not record it", which is a claim
    # about the software, and the true claim is about the filesystem.
    dead = fsheadroom.row("/proc/self/no/such/path")
    assert set(dead) == set(row), (set(dead), set(row))
    assert all(v is None for v in dead.values()), dead


def case_the_run_row_carries_it_in_all_three_writers():
    """The third-site guard, and it is the reason this case exists at all.

    tools/twatch.py appends to runs-<host>.ndjson from THREE places, and the
    comments on two of them record a fix that reached one writer and not its
    siblings -- twice. `new_red` sat as a literal [] on the pin row for weeks
    while every other row in the same archive carried a measurement. A field
    added to one writer by hand is a field that will be missing from two.
    """
    src = open(os.path.join(HERE, "twatch.py"), encoding="utf-8").read()
    n = src.count("json.dumps({**fs_row(")
    assert n == 3, (
        "expected all 3 runs-<host>.ndjson writers to spread fs_row(); found "
        "%d. A new writer must carry it too -- that is the whole point of this "
        "case." % n)
    # ...and the infra record, which has no report to hang a field on and is
    # therefore the one a report-assembly patch skips. It is also the only row
    # the 2026-09-07 outage produced: ~290 of them, none able to say whether
    # the box had room.
    assert "st[\"infra\"].update(fs_row(" in src, (
        "the infra record does not carry the headroom reading, which is the "
        "only kind of row the outage this guards against actually wrote")


def case_the_reading_is_labelled_start_or_after():
    """A start-of-run reading and an after-the-fact one are different claims.

    A run that died BECAUSE the filesystem filled has usually had its scratch
    reaped by the time twatch looks, so the late reading can come back healthy
    for exactly the run that was not. Recording it anyway beats recording
    nothing; mislabelling it does not.
    """
    spec = importlib.util.spec_from_file_location(
        "twatch_fsrow", os.path.join(HERE, "twatch.py"))
    tw = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(tw)
    from_report = tw.fs_row({"fs_at": "start", "fs_inodes_free": 8,
                             "fs_inodes_total": 1048576,
                             "fs_bytes_free_mb": 43000,
                             "fs_bytes_total_mb": 47000})
    assert from_report["fs_at"] == "start", from_report
    assert from_report["fs_inodes_free"] == 8, (
        "the report's own start-of-run reading was discarded and re-sampled; "
        "that is the reading that explains the run")
    assert tw.fs_row(None)["fs_at"] == "after", tw.fs_row(None)


def case_the_host_fingerprint_gains_disk_without_moving():
    """Adding fields to hosts.json must not make every box look like new hardware.

    fp_of_hardware() filters to HW_KEYS, so the scratch fields ride along
    without entering the hash. If they ever did, the epoch machinery would
    record a hardware change on every fleet box on the first run after a
    filesystem grew -- and free space moves every minute.
    """
    spec = importlib.util.spec_from_file_location(
        "twatch_hwfp", os.path.join(HERE, "twatch.py"))
    tw = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(tw)
    hw = tw.host_hardware()
    assert "scratch_inodes_total" in hw, sorted(hw)
    assert "scratch_bytes_total_mb" in hw, sorted(hw)
    base = tw.fp_of_hardware(hw)
    moved = dict(hw, scratch_inodes_total=1, scratch_bytes_total_mb=1,
                 scratch="/elsewhere")
    assert tw.fp_of_hardware(moved) == base, (
        "the scratch fields entered the hardware fingerprint; every host in "
        "the fleet would record a spurious hardware epoch")
    # ...and the FREE numbers must NOT be here: a fingerprint answers "is this
    # the same machine", and free space is a property of the minute.
    assert not any("free" in k for k in hw), (
        [k for k in hw if "free" in k])


def case_tmpdir_is_pinned_and_beats_the_parent():
    """The producer fix, and the assertion is about MECHANISM, not about a field.

    Asserting job_env()["TMPDIR"] is set would pass on a pass-through, and a
    pass-through is exactly what was there before: TMPDIR sat in ENV_ALLOW, read
    by ~20 tools/*.sh and by every tempfile call, and set by nothing in the
    repo. So this drives a real subprocess through the real environment and
    asks where its mkdtemp actually landed.
    """
    env = dict(os.environ)
    env["TMPDIR"] = "/tmp/PARENT-MUST-NOT-WIN"
    spec = importlib.util.spec_from_file_location(
        "tm_env", os.path.join(HERE, "testmgr.py"))
    tm = importlib.util.module_from_spec(spec)
    old = os.environ.get("TMPDIR")
    os.environ["TMPDIR"] = "/tmp/PARENT-MUST-NOT-WIN"
    try:
        spec.loader.exec_module(tm)
        allow = tm.job_env()
        assert allow["TMPDIR"] == tm.JOB_TMP, (
            "the parent's TMPDIR won: the pin is a pass-through, not a set — "
            "%r vs %r" % (allow["TMPDIR"], tm.JOB_TMP))
        # Both branches of job_env(), because a name in ENV_ALLOW *and*
        # BASE_ENV_KEEP resolves differently depending on which one runs: the
        # allowlist loop assigns after the BASE_ENV_KEEP copy.
        os.environ["TESTMGR_INHERIT_ENV"] = "1"
        assert tm.job_env()["TMPDIR"] == tm.JOB_TMP, (
            "the pin is lost under TESTMGR_INHERIT_ENV=1")
        os.environ.pop("TESTMGR_INHERIT_ENV", None)
        assert "TMPDIR" not in tm.ENV_ALLOW, (
            "TMPDIR is in BOTH ENV_ALLOW and BASE_ENV_KEEP; the two branches "
            "of job_env() disagree about which wins")
        assert tm.JOB_TMP.startswith(tm.RUN_TMP + os.sep), (
            "JOB_TMP is outside RUN_TMP, so it inherits neither teardown: "
            "%r" % tm.JOB_TMP)

        # The mechanism itself: a child under this environment must land inside.
        got = subprocess.run(
            [sys.executable, "-c",
             "import tempfile; print(tempfile.mkdtemp(prefix='pindevtest-'))"],
            env=tm.job_env(), capture_output=True, text=True, timeout=60)
        assert got.returncode == 0, got.stderr
        landed = got.stdout.strip()
        try:
            assert landed.startswith(tm.JOB_TMP + os.sep), (
                "a job's mkdtemp landed at %r, outside the pinned TMPDIR %r — "
                "which is where ~150 devtest sites have been leaking"
                % (landed, tm.JOB_TMP))
        finally:
            shutil.rmtree(landed, ignore_errors=True)
    finally:
        if old is None:
            os.environ.pop("TMPDIR", None)
        else:
            os.environ["TMPDIR"] = old


def case_the_reaper_spares_fresh_live_and_foreign():
    """The reaper's NEGATIVE controls, which are the ones that can hurt.

    A reaper that removes too much is worse than the leak: /tmp is shared, and
    the three things it must never touch are a directory that is young, one
    whose owning process is alive, and one that is not ours at all.
    """
    root = tempfile.mkdtemp(prefix="reapdevtest-")
    try:
        old = time.time() - 48 * 3600

        def mk(name, aged=True):
            p = os.path.join(root, name)
            os.makedirs(p)
            open(os.path.join(p, "f"), "w").close()
            if aged:
                os.utime(p, (old, old))
            return p

        stale = mk("tstate-at.DEVTEST")             # ours, old, dead  -> goes
        fresh = mk("tstate-at.FRESH", aged=False)   # ours, young      -> stays
        live = mk("tstate-at.%d" % os.getpid())     # ours, old, ALIVE -> stays
        foreign = mk("someone-elses-work")          # not ours         -> stays

        out = subprocess.run(
            [os.path.join(HERE, "reap_tmp.sh"), "-a", "6"],
            env=dict(os.environ, TESTTMP=root),
            capture_output=True, text=True, timeout=300)
        assert out.returncode == 0, out.stdout + out.stderr

        assert not os.path.exists(stale), (
            "the reaper did not reclaim a stale dir with a known prefix — it "
            "cannot fail, and a guard that cannot fail prints PASS\n" + out.stdout)
        for keep, why in ((fresh, "younger than the age cutoff"),
                          (live, "its pid is still alive"),
                          (foreign, "no tool in this repo creates that prefix")):
            assert os.path.isdir(keep), (
                "the reaper removed %s, which it must spare because %s\n%s"
                % (keep, why, out.stdout))
    finally:
        shutil.rmtree(root, ignore_errors=True)


def case_the_reaper_refuses_a_dangerous_root():
    for bad in ("", "/"):
        out = subprocess.run(
            [os.path.join(HERE, "reap_tmp.sh"), "-n"],
            env=dict(os.environ, TESTTMP=bad),
            capture_output=True, text=True, timeout=60)
        assert out.returncode == 2, (
            "TESTTMP=%r was accepted; a maxdepth-1 name glob at the filesystem "
            "root is not a mistake anyone gets to make twice\n%s"
            % (bad, out.stdout + out.stderr))


def case_the_logdir_budget_counts_inodes_not_only_dirs():
    """LOGDIR_KEEP_MAX bounds directories, and a directory is not a unit of storage.

    Measured 2026-09-10: 40 log dirs is 2,747 inodes on plexus (quick tiers, 67
    files each) and ~190,000 on seven (fulls, ~9,070 each) -- 18% of that box's
    tmpfs, inside budget, forever. A bound cannot see a resource it is not
    denominated in.
    """
    spec = importlib.util.spec_from_file_location(
        "tm_budget", os.path.join(HERE, "testmgr.py"))
    tm = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(tm)
    assert getattr(tm, "LOGDIR_KEEP_INODES", 0) > 0, (
        "there is no inode budget on the log dirs, only a count and an age")
    # The bounded walk must actually stop early, or the sweep pays ~9,000 stats
    # per dir per run to re-derive a number that stopped mattering at the cap.
    # A NESTED tree, because the property is "stops DESCENDING", and a flat
    # directory cannot show it: os.walk yields the whole flat dir in one step,
    # so any implementation returns the full count and the assertion passes on
    # a walk that never gives up. The first draft of this case did exactly that
    # and was a guard that could not fail.
    d = tempfile.mkdtemp(prefix="budgetdevtest-")
    try:
        for i in range(40):
            sub = os.path.join(d, "s%02d" % i)
            os.makedirs(sub)
            for j in range(10):
                open(os.path.join(sub, "f%d" % j), "w").close()
        total = tm._count_inodes(d, 10_000)
        assert total == 40 + 400, total
        early = tm._count_inodes(d, 25)
        assert early < total, (
            "the walk did not give up at the cap: %d of %d — a full-tier log "
            "dir is ~9,000 stats, paid on every run to re-derive a number that "
            "stopped mattering when it crossed the line" % (early, total))
        assert early > 25, early      # ...but it did answer the question asked
    finally:
        shutil.rmtree(d, ignore_errors=True)


def case_testmgr_reports_infra_not_red_when_it_cannot_run():
    """A box with no room must not be able to say "master is broken".

    write_infra_report() emits verdict INFRA with NO jobs, so nothing can be
    diffed into a NEW-RED, no ledger entry opens and no bisect can be
    manufactured out of it. That emitter is shared with the unbuildable-compiler
    path deliberately: two INFRA conditions with two emitters is how one of them
    drifts.
    """
    src = open(os.path.join(HERE, "testmgr.py"), encoding="utf-8").read()
    assert src.count("def write_infra_report(") == 1, "expected one INFRA emitter"
    assert "return write_infra_report(" in src, (
        "report_build_failure() no longer routes through the shared emitter")

    spec = importlib.util.spec_from_file_location(
        "tm_infra", os.path.join(HERE, "testmgr.py"))
    tm = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(tm)

    fd, path = tempfile.mkstemp(suffix=".json")
    os.close(fd)
    try:
        class Args:
            tier = "quick"
            report_json = path
        rc = tm.write_infra_report(Args(), "scratch filesystem too tight: test")
        assert rc == 1, rc
        rep = json.load(open(path))
        assert rep["verdict"] == "INFRA", rep["verdict"]
        assert rep["jobs"] == [], (
            "the INFRA report carries jobs; those diff to NEW-RED and a bisect "
            "then accuses an innocent commit")
        assert "fs_inodes_free" in rep, (
            "the INFRA report has no headroom reading — and it is the only "
            "report the outage this guards against would have produced")
    finally:
        os.unlink(path)


CASES = [v for k, v in sorted(globals().items()) if k.startswith("case_")]

if __name__ == "__main__":
    bad = 0
    for c in CASES:
        try:
            c()
            print("  ok   %s" % c.__name__)
        except Exception as e:                       # noqa: BLE001
            bad += 1
            print("  FAIL %s: %s" % (c.__name__, fail_detail(e)))
    print("%s: %d/%d green" % (os.path.basename(__file__),
                               len(CASES) - bad, len(CASES)))
    sys.exit(1 if bad else 0)
