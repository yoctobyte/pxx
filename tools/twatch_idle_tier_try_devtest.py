#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""The idle ladder must publish that it ENTERED a tier run.

Why: on 2026-09-06 the fleet spent an evening on "why has no full tier run
since 18:37Z" and could not answer, from published state, whether a full had
even been ENTERED.  A full never started and one started-then-aborted are
indistinguishable in the archive, and only the second is what a commitment
window describes -- so the two candidate explanations could not be separated.

`last_breadth_try` covers the RESERVED breadth path only.  `note_idle_abort` is
called for `verify-request` and `pin-verify` only.  The idle ladder -- the path
that actually produced every `full` that day -- recorded nothing, so the one
phase under investigation was the only one leaving no trace.
"""

import json
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import twatch  # noqa: E402


class _Clone(object):
    def __init__(self, path):
        self.path = path


def _fresh():
    d = tempfile.mkdtemp(prefix="twatch-idletry-")
    os.makedirs(os.path.join(d, twatch.TSTATE_REL), exist_ok=True)
    return _Clone(d)


def case_entering_a_tier_is_published():
    c = _fresh()
    twatch.note_idle_tier_try(c, "seven", "a" * 40, "full")
    st = twatch.load_state(c, "seven")
    rec = st.get("last_idle_tier_try")
    assert rec, "the idle ladder published nothing on entering a tier"
    assert rec["sha"] == "a" * 40, rec
    assert rec["tier"] == "full", rec
    assert rec.get("date"), "no date: an attempt with no time cannot be aged"


def case_it_records_the_ATTEMPT_not_the_outcome():
    """The whole point: an entry that never lands must still leave a trace.

    note_idle_tier_try is called BEFORE test_sha, so nothing about the run's
    result reaches it. This asserts the shape that makes an aborted run
    visible -- if someone later moves the call after the run "so it records
    real work", this case is what says no.
    """
    c = _fresh()
    twatch.note_idle_tier_try(c, "seven", "b" * 40, "full")
    rec = twatch.load_state(c, "seven")["last_idle_tier_try"]
    assert set(rec) == {"sha", "tier", "date"}, (
        "an outcome field leaked in: %s -- this records the ATTEMPT" % sorted(rec))


def case_a_later_attempt_replaces_an_earlier_one():
    c = _fresh()
    twatch.note_idle_tier_try(c, "seven", "c" * 40, "native")
    twatch.note_idle_tier_try(c, "seven", "d" * 40, "full")
    rec = twatch.load_state(c, "seven")["last_idle_tier_try"]
    assert rec["sha"] == "d" * 40 and rec["tier"] == "full", rec


def case_it_does_not_disturb_the_neighbouring_records():
    """last_breadth_try and idle_yield answer different questions; this must
    not overwrite either, or the fix re-creates the blind spot elsewhere."""
    c = _fresh()
    st = twatch.load_state(c, "seven")
    st["last_breadth_try"] = {"sha": "e" * 40, "date": "2026-09-05T21:51:18Z"}
    st["idle_yield"] = {"phase": "pin-verify", "target": "f" * 40, "aborts": 2}
    twatch.save_state(c, "seven", st)

    twatch.note_idle_tier_try(c, "seven", "0" * 40, "full")

    st2 = twatch.load_state(c, "seven")
    assert st2["last_breadth_try"]["sha"] == "e" * 40, st2["last_breadth_try"]
    assert st2["idle_yield"]["aborts"] == 2, st2["idle_yield"]
    assert st2["last_idle_tier_try"]["sha"] == "0" * 40


def case_the_idle_ladder_ACTUALLY_CALLS_IT():
    """AIMING. Every case above tests the helper; none proves the main loop
    reaches it, and a helper nothing calls publishes nothing.

    Asserted against the source because the write lives inside the daemon's
    main loop, which no unit test drives. The precise thing that must hold: the
    call sits BEFORE the idle-ladder's `test_sha(..., nxt, ...)`, because an
    attempt recorded after the run cannot record an attempt that was aborted --
    which is the only case this exists for.
    """
    src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "twatch.py"), encoding="utf-8").read()
    call = "note_idle_tier_try(clone, host, tested, nxt)"
    run = "r = test_sha(clone, host, st, tested, nxt, full=True,"
    assert call in src, "the idle ladder does not call note_idle_tier_try"
    assert run in src, ("the idle-ladder test_sha call has been reshaped -- "
                        "re-aim this assertion rather than deleting it")
    assert src.index(call) < src.index(run), (
        "note_idle_tier_try runs AFTER the tier run; an aborted attempt would "
        "then leave no trace, which is the whole failure this records")


def main():
    fails = 0
    for name, fn in sorted(globals().items()):
        if not name.startswith("case_"):
            continue
        try:
            fn()
            print("  ok   %s" % name)
        except AssertionError as e:
            fails += 1
            print("  FAIL %s: %s" % (name, e))
    print("twatch-idle-tier-try: %d failure(s)" % fails)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
