#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest for testmgr's co-tenancy handling (bug-t-watcher-dev-contention-false-newred).

The run lock is per-repo, so two testmgrs from DIFFERENT clones — the watcher
daemon's dedicated clone and a dev checkout — never see each other. Each sizes
its parallelism to the whole box, together they oversubscribe it ~2x, and the
long jobs lose by being KILLED. The tell is `Terminated` in the log with the
compile line reading `ok:`: no verdict was ever produced. tstate published one
such job as NEW-RED at e584d7b4 while the dev session's own run at the same
tree called the same job "flaky (recovered on retry)".

What must hold:

  * a kill (SIGTERM/SIGKILL) while a co-tenant is live -> RETRY, any class;
  * the same kill on an idle box -> still RED, single-shot stays single-shot;
  * a genuine nonzero exit -> RED even under contention (a wrong answer is a
    wrong answer, and laundering it would be far worse than the bug);
  * retries stay bounded by RUN_RETRY_TRIES;
  * timeouts stretch by PEER_TIME_FACTOR only while contended.

Drives Manager.reap() directly with stub processes: no jobs are launched, no
repo state is touched, nothing is timing-dependent.
Run: python3 tools/testmgr_contention_devtest.py
"""
import argparse
import pathlib
import signal
import subprocess
import sys
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import testmgr  # noqa: E402


class StubProc:
    """Just enough subprocess.Popen for reap(): a fixed poll() result."""

    def __init__(self, rc):
        self._rc = rc
        self.pid = -1              # never signalled: kill_group is stubbed out

    def poll(self):
        return self._rc

    def wait(self, timeout=None):
        return self._rc


def make_manager(job_cls="unit"):
    args = argparse.Namespace(tier="quick", serial=False, jobs=2, deadline=3600,
                              fail_fast=False, job=None, list=False)
    job = testmgr.Job("test-core", 1,
                      ["./pascal26 test/test_interface_mainbody_ascast_temp.pas /tmp/x26",
                       "/tmp/x26; test \"$?\" = \"0\""])
    job.cls = job_cls
    mgr = testmgr.Manager([job], args, 1.0, "/tmp")
    # Never send a real signal from a test. A stub pid handed to killpg() is
    # not merely useless, it is dangerous — killpg(0) would take out this
    # process group, which is how the run lock's own kill path once SIGKILLed
    # the session that was testing it (see kill_run).
    mgr.killed = []
    mgr.kill_group = lambda job, sig=None: mgr.killed.append(job.name)
    return mgr, job


def running(mgr, job, rc, elapsed=1.0):
    """Put the job in the running set as if it had just been reaped."""
    job.proc = StubProc(rc)
    job.t0 = time.monotonic() - elapsed
    job.t1 = None
    job.status = "running"
    job.attempts = max(1, job.attempts)
    mgr.running = [job]
    mgr.queue = []


def with_peer(mgr):
    """As if poll_peers() had just found another clone's run."""
    mgr.peer_last_seen = time.monotonic()
    mgr.peer_repos.add("/home/neo/trackt-watch")


def case_kill_under_contention_retries():
    mgr, job = make_manager()
    with_peer(mgr)
    running(mgr, job, rc=-signal.SIGTERM)
    done = mgr.reap()
    assert done == [], f"job was finalized instead of retried: {job.status}"
    assert job.status == "queued", f"expected requeue, got {job.status}"
    assert job in mgr.queue, "job was not put back on the queue"
    return "SIGTERM + co-tenant -> requeued"


def case_kill_on_an_idle_box_is_still_red():
    """The whole safety argument: contention is what makes a kill meaningless,
    so with no contention nothing changes."""
    mgr, job = make_manager()
    running(mgr, job, rc=-signal.SIGTERM)
    done = mgr.reap()
    assert job.status == "fail", f"idle-box kill was laundered to {job.status}"
    assert done == [job]
    return "SIGTERM alone -> still FAIL"


def case_wrong_answer_is_red_even_under_contention():
    """A nonzero EXIT is a verdict; contention must never launder one."""
    mgr, job = make_manager()
    with_peer(mgr)
    running(mgr, job, rc=1)
    done = mgr.reap()
    assert job.status == "fail", f"a real failure was retried away: {job.status}"
    assert done == [job]
    return "rc=1 + co-tenant -> FAIL"


def case_retries_are_bounded():
    mgr, job = make_manager()
    with_peer(mgr)
    job.attempts = testmgr.RUN_RETRY_TRIES
    running(mgr, job, rc=-signal.SIGKILL)
    done = mgr.reap()
    assert job.status == "fail", f"unbounded retry: {job.status}"
    assert done == [job]
    return f"attempt {testmgr.RUN_RETRY_TRIES}/{testmgr.RUN_RETRY_TRIES} -> FAIL"


def case_timeout_stretches_only_while_contended():
    mgr, job = make_manager()
    job.timeout = 100.0
    job.t0 = time.monotonic()
    assert mgr.effective_timeout(job) == 100.0, "stretched with no co-tenant"
    with_peer(mgr)
    assert mgr.effective_timeout(job) == 100.0 * testmgr.PEER_TIME_FACTOR, \
        mgr.effective_timeout(job)
    return f"{testmgr.PEER_TIME_FACTOR:.0f}x only while contended"


def case_timeout_under_contention_retries():
    mgr, job = make_manager()
    job.timeout = 1.0
    with_peer(mgr)
    # past even the stretched budget
    running(mgr, job, rc=None, elapsed=1.0 * testmgr.PEER_TIME_FACTOR + 5.0)
    done = mgr.reap()
    assert mgr.killed == [job.name], f"the timeout did not kill the job: {mgr.killed}"
    assert done == [], f"timed-out job finalized as {job.status}"
    assert job.status == "queued", f"expected requeue, got {job.status}"
    return "timeout + co-tenant -> requeued"


def case_peer_detection_excludes_our_own_repo():
    """foreign_runs() must not report US: our own clone is what the per-repo
    lock already covers, and self-detection would stretch every timeout on a
    box that is not contended at all."""
    for pid, repo, tier, age in testmgr.foreign_runs():
        assert repo != testmgr.REPO, f"own repo reported as a peer: {repo}"
    return f"{len(testmgr.foreign_runs())} peer run(s) on this box right now"


def case_wrapper_process_is_not_a_run():
    """A process that merely carries the command line — `timeout 600 python3
    tools/testmgr.py`, `bash -c "... testmgr.py ..."`, gate.sh — matches the
    argv scan but is not a run. Before this was filtered, a solo run detected
    its OWN timeout wrapper as a rival clone and stretched every budget.
    """
    # The trailing `; true` matters: bash exec-optimizes a lone simple
    # command and the comment (with it, the argv we are testing) disappears.
    script = f"sleep 30; true # {testmgr.REPO}/tools/testmgr.py"
    wrapper = subprocess.Popen(["bash", "-c", script],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        time.sleep(0.2)
        with open(f"/proc/{wrapper.pid}/cmdline", "rb") as f:
            argv = f.read().decode().split("\0")
        assert any(a.endswith("testmgr.py") for a in argv), \
            "test setup: the wrapper does not match the argv scan at all"
        pids = [r[0] for r in testmgr.find_runs()]
        assert wrapper.pid not in pids, \
            f"a bash wrapper was counted as a testmgr run (pid {wrapper.pid})"
    finally:
        wrapper.kill()
        wrapper.wait()
    return "bash/timeout wrapper ignored"


CASES = [
    case_kill_under_contention_retries,
    case_kill_on_an_idle_box_is_still_red,
    case_wrong_answer_is_red_even_under_contention,
    case_retries_are_bounded,
    case_timeout_stretches_only_while_contended,
    case_timeout_under_contention_retries,
    case_peer_detection_excludes_our_own_repo,
    case_wrapper_process_is_not_a_run,
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
    print("co-tenancy handling OK" if rc == 0 else "co-tenancy handling BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
