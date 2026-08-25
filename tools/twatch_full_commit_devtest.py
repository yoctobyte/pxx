#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a breadth run that is far enough along FINISHES.

Until 2026-08-25 every idle-phase run was discarded the moment a testable push
landed. That was right when a push meant "the tree you are testing is now
wrong". On a fast-moving `dev` branch it means "there is more work behind this",
and the arithmetic turns hostile: a full tier is ~40 min of wall at the 6-core
throttle, testable pushes arrive every ~26 min on average, so a run that
restarts on every push completes only in the tail of the gap distribution.
Observed directly: a full tier was discarded at 73 of 3057 jobs and its
replacement started from zero. The failure mode is not "degraded breadth", it
is ZERO breadth on any working day — while every native verdict stays green and
`--status` says UP, so nothing announces it.

So the breadth run commits after `full_commit_secs`. The cases below pin the
three things that make that safe rather than merely effective:

  * the fast native verdict — the one the lanes steer by — is untouched;
  * STOP still aborts instantly, so the commitment cannot wedge the daemon;
  * a committed run stops fetching, because it would act on nothing it learned.

No git anywhere: every case is about the policy inside the closure.
Run: tools/twatch_full_commit_devtest.py   (exit 0 = pass)
"""
import importlib.util
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tw", os.path.join(HERE,
                                                                "twatch.py"))
tw = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tw)

TESTED = "a" * 40
NEWER = "b" * 40
REAL_MONOTONIC = time.monotonic

# The FakeClone answers "is there testable work" directly, so needs_test never
# reaches git. A real repo here would only add a way for these cases to fail for
# a reason that is not the subject.
tw.needs_test = lambda repo, sha: sha != "docs-only"


class FakeClone:
    """Counts fetches, so a post-commitment poll can be proven silent."""

    def __init__(self, head=TESTED, testable=True):
        self.path = "/nonexistent"
        self.branch = "dev"
        self.head = head
        self.testable = testable
        self.fetches = 0

    def fetch(self):
        self.fetches += 1

    def remote_head(self):
        return self.head

    def commits_between(self, a, b):
        return ["c" * 40] if self.testable else ["docs-only"]


def clock(t):
    """Pin the closure's clock. Restored by the runner after every case."""
    tw.time.monotonic = lambda: t


def t_a_push_preempts_before_the_commitment_point():
    c = FakeClone(head=NEWER)
    clock(0.0)
    p = tw.make_preempted(c, TESTED, commit_after=300)
    clock(299.0)
    assert p(), "a push 299s into a 300s window must still preempt — inside " \
                "the window the behaviour is exactly what it always was"
    return "the window is unchanged"


def t_a_push_does_not_preempt_after_it():
    c = FakeClone(head=NEWER)
    clock(0.0)
    p = tw.make_preempted(c, TESTED, commit_after=300)
    clock(301.0)
    assert not p(), "past commit_after the run must be allowed to finish — " \
                    "this is the whole fix"
    return "committed runs survive a push"


def t_commitment_is_sticky_and_stops_fetching():
    c = FakeClone(head=NEWER)
    clock(0.0)
    p = tw.make_preempted(c, TESTED, commit_after=300)
    clock(400.0)
    p()
    settled = c.fetches
    for t in (430.0, 460.0, 490.0):
        clock(t)
        assert not p(), "commitment must be sticky; it lapsed at %.0fs" % t
    assert c.fetches == settled, \
        "%d fetch(es) after commitment: a run that will act on nothing it " \
        "learns must not ask" % (c.fetches - settled)
    return "sticky, and silent on the network"


def t_stop_still_aborts_a_committed_run():
    c = FakeClone(head=NEWER)
    clock(0.0)
    p = tw.make_preempted(c, TESTED, commit_after=300)
    clock(999.0)
    p()
    tw.STOP = True
    try:
        assert p(), "STOP must outrank the commitment — a daemon that cannot " \
                    "be stopped is worse than the bug being fixed here"
    finally:
        tw.STOP = False
    return "ctrl-C wins"


def t_the_native_path_is_untouched():
    """The fast verdict passes no commit_after and must stay fully preemptive."""
    c = FakeClone(head=NEWER)
    clock(0.0)
    p = tw.make_preempted(c, TESTED)
    for t in (10.0, 3000.0, 99999.0):
        clock(t)
        assert p(), "without commit_after nothing may change; it stopped " \
                    "preempting at %.0fs" % t
    return "native still preempts at every moment"


def t_a_tstate_only_publish_never_preempts():
    """Our own fast-phase publish must not abort the work it queued."""
    c = FakeClone(head=NEWER, testable=False)
    clock(0.0)
    p = tw.make_preempted(c, TESTED, commit_after=300)
    clock(100.0)
    assert not p(), "only testable commits preempt"
    return "docs/tstate movement is not work"


def main():
    rc = 0
    for fn in (t_a_push_preempts_before_the_commitment_point,
               t_a_push_does_not_preempt_after_it,
               t_commitment_is_sticky_and_stops_fetching,
               t_stop_still_aborts_a_committed_run,
               t_the_native_path_is_untouched,
               t_a_tstate_only_publish_never_preempts):
        try:
            print("  ok   %s — %s" % (fn.__name__, fn()))
        except Exception as e:              # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s"
                  % (fn.__name__, type(e).__name__, fail_detail(e)))
        finally:
            tw.time.monotonic = REAL_MONOTONIC
    print("breadth commitment OK" if rc == 0 else "breadth commitment BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
