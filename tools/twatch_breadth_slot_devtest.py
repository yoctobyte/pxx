#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: breadth takes a slot when it is stale, and cannot starve the fast one.

`bug-t-the-push-rate-starves-breadth-coverage-entirely` concluded in August 2026
that the fix was "resumability plus bounding consecutive idle, NOT reserving a
slot". Under the measurement it had, that was right: the box was idle 54% of the
window, so breadth did not need a reservation — it needed the unfinishable item
ahead of it to stop holding the queue.

The premise expired. After this box became a workstation and the watcher was
capped at 6 of 12 cores, a native run costs ~490s (was ~246s) and ~9 testable
commits land during one. `do_test` is therefore true on essentially every cycle,
the idle ladder is unreachable, and breadth cannot START — which also makes the
commitment point that lets a breadth run FINISH inert.

So the reservation is narrow by construction, and these cases are the fence
around it: stale-only, backoff-guarded, and never firing on a host that has
tested nothing. The failure mode being fenced off is the one that matters more
than breadth — a breadth run that keeps failing to land taking every slot
forever, so the fast verdict every lane reads simply stops.

Run: tools/twatch_breadth_slot_devtest.py   (exit 0 = pass)
"""
import calendar
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

NOW = calendar.timegm(time.strptime("2026-08-25T20:00:00Z",
                                    "%Y-%m-%dT%H:%M:%SZ"))


def iso(secs_ago):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(NOW - secs_ago))


def state(full_age=None, try_age=None):
    st = {}
    if full_age is not None:
        st["last_full"] = {"sha": "a" * 40, "date": iso(full_age),
                           "tier": "full", "verdict": "GREEN"}
    if try_age is not None:
        st["last_breadth_try"] = {"sha": "b" * 40, "date": iso(try_age)}
    return st


def t_fresh_breadth_does_not_take_the_slot():
    """The ordinary case, and it must stay ordinary: a fresh push gets the
    fast verdict, every time, as long as breadth is current."""
    why = tw.breadth_overdue(state(full_age=600), NOW)
    assert why == "", "breadth stole a slot 10 minutes after completing: %r" % why
    why = tw.breadth_overdue(state(full_age=tw.BREADTH_STALE_SECS - 60), NOW)
    assert why == "", "fired one minute before the threshold"
    return "fast verdict keeps the slot while breadth is current"


def t_stale_breadth_takes_the_slot():
    why = tw.breadth_overdue(state(full_age=tw.BREADTH_STALE_SECS + 60), NOW)
    assert why, "breadth past its staleness threshold did not claim a slot"
    assert "old" in why, "the reason must name the age: %r" % why
    return why


def t_a_host_with_no_breadth_at_all_claims_one():
    why = tw.breadth_overdue(state(), NOW)
    assert why, "a host that has never completed breadth must claim a slot"
    assert "yet" in why, "the reason should say there is none: %r" % why
    return why


def t_the_backoff_stops_breadth_from_taking_every_slot():
    """The important one. A breadth run that does not LAND leaves last_full
    untouched, so the staleness test stays true forever. Without a backoff the
    reservation would fire on every cycle and the fast verdict — the signal the
    lanes actually steer by — would stop entirely."""
    st = state(full_age=tw.BREADTH_STALE_SECS + 3600, try_age=60)
    assert tw.breadth_overdue(st, NOW) == "", \
        "breadth claimed a second slot one minute after a failed attempt"
    st = state(full_age=tw.BREADTH_STALE_SECS + 3600,
               try_age=tw.BREADTH_RETRY_SECS - 60)
    assert tw.breadth_overdue(st, NOW) == "", "backoff lapsed early"
    st = state(full_age=tw.BREADTH_STALE_SECS + 3600,
               try_age=tw.BREADTH_RETRY_SECS + 60)
    assert tw.breadth_overdue(st, NOW), "backoff never expires — breadth is dead"
    return "one attempt per %s, then it may try again" % tw.fmt_age(
        tw.BREADTH_RETRY_SECS)


def t_a_landed_run_clears_the_claim_even_inside_the_backoff():
    """Success is what clears it, not the passage of time: a breadth run that
    COMPLETED must return the slot immediately, backoff or no backoff."""
    st = state(full_age=60, try_age=60)
    assert tw.breadth_overdue(st, NOW) == "", \
        "a completed breadth run did not release the slot"
    return "landing releases it at once"


def t_an_unparseable_date_does_not_wedge_the_daemon():
    """State is JSON on disk and can be anything. The safe direction here is
    to CLAIM the slot (breadth is what is missing), never to raise."""
    st = {"last_full": {"sha": "a" * 40, "date": "not-a-date"}}
    why = tw.breadth_overdue(st, NOW)
    assert isinstance(why, str), "returned %r instead of a reason string" % (why,)
    return "garbage date -> %r" % (why or "no claim")


def t_breadth_in_flight_is_visible_to_a_remote_reader():
    """--status must not call a busy watcher DOWN.

    A reserved breadth run pauses the fast verdict for 40-67 minutes, so commits
    cross the 45-minute grace and `--status` reports DOWN — which tells every
    dev agent to run its own full gate, ten minutes each, to replace a matrix
    that is running right now. A remote reader cannot see the daemon's phase
    heartbeat (it is a file in the clone), so `last_breadth_try` is published in
    the host state and written BEFORE the run for exactly this reason.
    """
    st = state(full_age=tw.BREADTH_STALE_SECS + 3600, try_age=600)
    st["last"] = {"sha": "c" * 40, "date": iso(1800), "verdict": "GREEN"}
    bf = tw.breadth_inflight(st, NOW)
    assert bf, "a breadth run 10 minutes in was not visible as in-flight"
    sha, started = bf
    assert sha == "b" * 40 and 590 < started < 610, "wrong sha/age: %r" % (bf,)
    return "in flight, %ds in" % started


def t_a_landed_run_ends_the_in_flight_claim():
    """Once a run lands, st["last"] moves past the claim and the pause is over.
    Without this the reader would suppress DOWN for the full bound after every
    successful breadth run — masking a real outage for up to two hours."""
    st = state(full_age=60, try_age=600)
    st["last"] = {"sha": "c" * 40, "date": iso(30), "verdict": "GREEN"}
    assert tw.breadth_inflight(st, NOW) is None, \
        "a completed run did not clear the in-flight claim"
    return "landing ends it"


def t_a_daemon_that_dies_mid_breadth_still_reports_down():
    """The bound is the whole reason this is safe to trust. A claim older than
    BREADTH_RETRY_SECS is stale, and DOWN becomes the honest answer again."""
    st = state(full_age=tw.BREADTH_STALE_SECS + 9999,
               try_age=tw.BREADTH_RETRY_SECS + 60)
    st["last"] = {"sha": "c" * 40, "date": iso(tw.BREADTH_RETRY_SECS + 600)}
    assert tw.breadth_inflight(st, NOW) is None, \
        "a stale claim still suppressed DOWN — a dead daemon would hide behind it"
    return "the claim expires after %s" % tw.fmt_age(tw.BREADTH_RETRY_SECS)


def t_a_host_that_never_claimed_breadth_is_not_in_flight():
    assert tw.breadth_inflight(state(full_age=600), NOW) is None
    assert tw.breadth_inflight({}, NOW) is None
    return "no claim, no suppression"


def main():
    rc = 0
    for fn in (t_fresh_breadth_does_not_take_the_slot,
               t_stale_breadth_takes_the_slot,
               t_a_host_with_no_breadth_at_all_claims_one,
               t_the_backoff_stops_breadth_from_taking_every_slot,
               t_a_landed_run_clears_the_claim_even_inside_the_backoff,
               t_an_unparseable_date_does_not_wedge_the_daemon,
               t_breadth_in_flight_is_visible_to_a_remote_reader,
               t_a_landed_run_ends_the_in_flight_claim,
               t_a_daemon_that_dies_mid_breadth_still_reports_down,
               t_a_host_that_never_claimed_breadth_is_not_in_flight):
        try:
            print("  ok   %s — %s" % (fn.__name__, fn()))
        except Exception as e:              # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s"
                  % (fn.__name__, type(e).__name__, fail_detail(e)))
    print("breadth slot OK" if rc == 0 else "breadth slot BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
