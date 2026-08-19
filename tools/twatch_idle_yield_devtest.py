#!/usr/bin/env python3
"""An idle phase that cannot finish must not hold the idle slot forever.

Shape 4 of bug-t-the-push-rate-starves-breadth-coverage-entirely. On 2026-08-19
platform breadth on HEAD did not run once in 5h13m while the watcher was idle
54% of that window: it sat behind pin verify, which outranks it deliberately,
needs ~21 contiguous minutes, was offered slices with a median of 299s, and
discards everything on abort. pin_verify_due never went false, so the branch
below it was never reached.

These checks pin the yield's exact shape, including the two ways it could be
wrong in the opposite direction: yielding too eagerly (inverting a priority
that exists for a real reason) and yielding permanently (the same starvation
pointed the other way).

Run: python3 tools/twatch_idle_yield_devtest.py
"""
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import twatch


class FakeClone:
    def __init__(self, path):
        self.path = path


PIN_A = "aaaaaaaaaaaa1111111111111111111111111111"
PIN_B = "bbbbbbbbbbbb2222222222222222222222222222"


def main():
    fails = []

    def check(cond, what):
        print(("  ok   " if cond else "  FAIL ") + what)
        if not cond:
            fails.append(what)

    def takes_slot(st, pin):
        """The ladder's actual guard, kept in one place so a change to the
        condition breaks this test rather than silently passing it."""
        return twatch.idle_aborts(st, "pin-verify", pin) < twatch.IDLE_YIELD_AFTER

    with tempfile.TemporaryDirectory() as tmp:
        clone, host = FakeClone(tmp), "testhost"
        twatch.save_state(clone, host, twatch.load_state(clone, host))

        print("pin verify keeps the slot while it is still plausibly using it")
        for i in range(twatch.IDLE_YIELD_AFTER - 1):
            st = twatch.load_state(clone, host)
            check(takes_slot(st, PIN_A), "slot held after %d abort(s)" % i)
            twatch.note_idle_abort(clone, host, "pin-verify", PIN_A)

        print("...and yields once it has proven it cannot")
        st = twatch.load_state(clone, host)
        check(takes_slot(st, PIN_A),
              "still held at %d aborts" % (twatch.IDLE_YIELD_AFTER - 1))
        twatch.note_idle_abort(clone, host, "pin-verify", PIN_A)
        st = twatch.load_state(clone, host)
        check(not takes_slot(st, PIN_A),
              "yields at IDLE_YIELD_AFTER (%d) aborts" % twatch.IDLE_YIELD_AFTER)

        print("the yield buys ONE turn, not a handover")
        twatch.clear_idle_yield(clone, host)
        st = twatch.load_state(clone, host)
        check(takes_slot(st, PIN_A),
              "pin verify has priority again on the very next cycle")

        print("a run that is NOT preempted resets the count")
        for _ in range(twatch.IDLE_YIELD_AFTER):
            twatch.note_idle_abort(clone, host, "pin-verify", PIN_A)
        check(not takes_slot(twatch.load_state(clone, host), PIN_A),
              "yielding after a fresh run of aborts")
        twatch.clear_idle_yield(clone, host)      # what a verdict does
        check(takes_slot(twatch.load_state(clone, host), PIN_A),
              "a completed verify restores full priority")

        print("a NEW pin starts with a full budget")
        for _ in range(twatch.IDLE_YIELD_AFTER):
            twatch.note_idle_abort(clone, host, "pin-verify", PIN_A)
        check(not takes_slot(twatch.load_state(clone, host), PIN_A),
              "old pin is out of budget")
        check(takes_slot(twatch.load_state(clone, host), PIN_B),
              "new pin is not charged for the old pin's aborts")
        check(twatch.idle_aborts(twatch.load_state(clone, host),
                                 "pin-verify", PIN_B) == 0,
              "counter reads 0 for an unseen target")

        print("the counter is per-phase, not global")
        check(twatch.idle_aborts(twatch.load_state(clone, host),
                                 "breadth", PIN_A) == 0,
              "another phase is not charged for pin verify's aborts")

        print("clearing is safe when nothing is pending")
        twatch.clear_idle_yield(clone, host)
        twatch.clear_idle_yield(clone, host)
        check(takes_slot(twatch.load_state(clone, host), PIN_A),
              "double clear leaves a usable state")

        print("the threshold preserves pin verify's priority")
        check(twatch.IDLE_YIELD_AFTER >= 2,
              "yields at worst one slot in two, never every other turn")

    print()
    if fails:
        print("FAILED %d check(s)" % len(fails))
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
