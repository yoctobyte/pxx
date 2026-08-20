#!/usr/bin/env python3
"""Guards for the DURATION discriminator that reaches a Makefile-inner timeout.

`timeout N` hardcoded inside a make recipe kills its child, the recipe returns
an ordinary nonzero, and make reports `Error 1`. testmgr therefore observes a
job that FAILED, never a job that ran out of time, and every piece of its
contention machinery is structurally unable to see it -- that is
bug-t-makefile-inner-timeouts-are-invisible-to-testmgrs-contention-logic, and
the measurement on that ticket found that ZERO of the ten sites propagate
`timeout`'s exit 124 to make.

So the exit status carries nothing and the DURATION is all that is left.
`Manager._inner_timeout_shaped()` reads it; `_retriable_contention()` decides.
The split is the thing under test: the shape check must never retry on its
own, because "took 9x as long and failed" without a co-tenant is a plausible
PERFORMANCE REGRESSION, and retrying that masks the finding.

Runs in milliseconds: no tier, no subprocess, no repo. Borrows the real
methods off Manager so a drift in production reddens these rather than
sailing past a local copy.

    python3 tools/testmgr_inner_timeout_retry_devtest.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import testmgr                                             # noqa: E402

FAILS = []


def check(cond, what):
    print("%s %s" % ("ok  " if cond else "FAIL", what))
    if not cond:
        FAILS.append(what)


class FakeJob:
    def __init__(self, exp_dur=40.0, t0=0.0, advisory=False, attempts=1):
        self.exp_dur = exp_dur
        self.t0 = t0
        self.advisory = advisory
        self.attempts = attempts
        self.name = "test-uforth#00"
        self.requeued = False


class FakeMgr:
    """Only what the two methods under test touch."""
    _inner_timeout_shaped = testmgr.Manager._inner_timeout_shaped
    _retriable_contention = testmgr.Manager._retriable_contention
    contended = testmgr.Manager.contended

    def __init__(self, peer_seen):
        self.peer_last_seen = peer_seen
        self.requeued = []

    def _requeue_retry(self, job, why):
        self.requeued.append((job, why))


# ------------------------------------------------------ the shape check ---
# A learned 40s job that failed after 360s. Every real inner ceiling in the
# Makefile (60/120/180/900) sits far enough above normal runtime that a kill
# by one overshoots like this.
mgr = FakeMgr(peer_seen=0.0)
check(mgr._inner_timeout_shaped(FakeJob(exp_dur=40.0, t0=0.0), 360.0),
      "a fail 9x longer than its learned duration is duration-shaped")

check(not mgr._inner_timeout_shaped(FakeJob(exp_dur=40.0, t0=0.0), 45.0),
      "a fail at ~1x its learned duration is NOT (that is a wrong VALUE)")

check(mgr._inner_timeout_shaped(FakeJob(exp_dur=40.0, t0=0.0),
                                40.0 * testmgr.INNER_TIMEOUT_RATIO),
      "the ratio boundary is inclusive — exactly RATIO x counts")

check(not mgr._inner_timeout_shaped(
          FakeJob(exp_dur=40.0, t0=0.0), 40.0 * testmgr.INNER_TIMEOUT_RATIO - 1),
      "one second under the boundary does not")

# The floor. A ratio is not evidence at every scale.
check(not mgr._inner_timeout_shaped(FakeJob(exp_dur=0.2, t0=0.0), 9.0),
      "a 0.2s job that took 9s is below the floor — 45x, still not evidence")
check(testmgr.INNER_TIMEOUT_FLOOR > 0 and testmgr.INNER_TIMEOUT_RATIO > 1.0,
      "the constants are sane (floor above zero, ratio above unity)")

# Fails closed with no baseline.
check(not mgr._inner_timeout_shaped(FakeJob(exp_dur=None, t0=0.0), 9999.0),
      "a job that has never passed here has no exp_dur, so no discriminator")
check(not mgr._inner_timeout_shaped(FakeJob(exp_dur=0.0, t0=0.0), 9999.0),
      "a stored exp_dur of 0.0 means corrupt metrics, not an instant job")
check(not mgr._inner_timeout_shaped(FakeJob(exp_dur=40.0, t0=None), 9999.0),
      "a job with no start time cannot have a duration")

# ------------------------------------------- the contention gate on top ---
# THE load-bearing guard: shape alone must not retry.
quiet = FakeMgr(peer_seen=0.0)          # no peer ever seen
job = FakeJob(exp_dur=40.0, t0=100.0)
check(quiet._inner_timeout_shaped(job, 460.0)
      and not quiet._retriable_contention(job, "why"),
      "duration-shaped on an IDLE box is NOT retried — it may be a real "
      "performance regression, and retrying would mask it")

busy = FakeMgr(peer_seen=150.0)         # peer seen while the job ran
job = FakeJob(exp_dur=40.0, t0=100.0)
check(busy._inner_timeout_shaped(job, 460.0)
      and busy._retriable_contention(job, "why") and busy.requeued,
      "duration-shaped WITH a co-tenant live is retried")

stale = FakeMgr(peer_seen=50.0)         # peer last seen BEFORE the job started
job = FakeJob(exp_dur=40.0, t0=100.0)
check(not stale._retriable_contention(job, "why"),
      "a peer that was gone before this job started does not excuse it")

busy = FakeMgr(peer_seen=150.0)
check(not busy._retriable_contention(
          FakeJob(exp_dur=40.0, t0=100.0, advisory=True), "why"),
      "an advisory job gates nothing, so a retry only burns time")

busy = FakeMgr(peer_seen=150.0)
check(not busy._retriable_contention(
          FakeJob(exp_dur=40.0, t0=100.0,
                  attempts=testmgr.RUN_RETRY_TRIES), "why"),
      "retries are still bounded by RUN_RETRY_TRIES")

# ------------------------------------------------------ the verdict word ---
# Relabelling these "timeout" would be more honest AND would silently suppress
# bisects that are sound today, because bisect_step refuses to bisect one.
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "testmgr.py")).read()
method = src.split("def _inner_timeout_shaped", 1)[1].split("\n    def ", 1)[0]
code = method.split('"""')[2]          # everything after the docstring
check("status" not in code and "job.cls" not in code,
      "_inner_timeout_shaped touches no status and no class — it proposes a "
      "SHAPE, it does not judge")

# ...and the coupling itself, at the source. The shape check is only safe
# because every caller routes it through the contention gate; a future branch
# that acts on the shape alone would turn a performance regression into a
# silent retry, and no runtime guard here can see that call site.
calls = [ln.strip() for ln in src.split("\n")
         if "_inner_timeout_shaped(" in ln
         and not ln.lstrip().startswith(("#", "def ", "@"))
         and "def _inner" not in ln]
check(len(calls) == 1, "exactly one caller of the shape check (found %d)"
      % len(calls))
check(all("_retriable_contention" in
          src.split(c, 1)[1].split("elif ", 1)[0] for c in calls),
      "every caller conjoins it with _retriable_contention — the shape never "
      "retries on its own")

print()
if FAILS:
    print("%d FAILED" % len(FAILS))
    sys.exit(1)
print("all guards green")
