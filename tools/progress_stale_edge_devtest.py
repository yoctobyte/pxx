#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Devtest: a blocked-by edge is a claim about the world at filing time.

Nothing re-checks it, because resolving a blocker is an event on the BLOCKER
and the edge lives on the DEPENDENT — at the moment the claim goes stale,
nobody is standing where it is written.

Measured repo-wide 2026-08-28: 14 live tickets named a closed blocker; five
were fully unblocked and all five sat in `blocked/`, which `ready`/`next` never
scan. One was p85.

THE SEVERITY SPLIT IS THE POINT, and it was measured rather than assumed.
`ready_tickets` keeps a ticket when every blocker is in `resolved_slugs`, so a
cleared edge in a RANKED folder suppresses nothing — the ticket ranks normally
and the edge is merely untidy. Failing on those would have reported 17 findings
of which 12 cost nobody anything, which is how a check earns the habit of being
scrolled past. `blocked/` is different in KIND: the folder means "has an unmet
blocker" and is never scanned, so a cleared ticket there is a contradiction
that also hides it.

The fourth case has ZERO instances today and was ALREADY handled:
`resolved_slugs` is `done | decided` and does NOT include `rejected/`, so a
ticket blocked by a rejected one can never satisfy its edge in ANY folder, and
moving it does not help. `BLOCKED-BY-REJECTED` has covered that since before
this ticket; it simply had no test. I wrote a second implementation of it
before noticing, which is the smell `normalise-dont-special-case.md` names —
the duplicate is gone and the guard is what the detour was worth.

Run: tools/progress_stale_edge_devtest.py   (exit 0 = pass)
"""
import importlib
import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from devtest_report import fail_detail  # noqa: E402

pg = importlib.import_module("progress")


def _board(tickets):
    """Build a Board over a throwaway tree. `tickets` is (status, slug, fm)."""
    tmp = tempfile.mkdtemp(prefix="stale-edge-")
    root = Path(tmp)
    for st in pg.STATUSES:
        (root / st).mkdir(parents=True, exist_ok=True)
    for st, slug, fm in tickets:
        body = ["---"] + ["%s: %s" % (k, v) for k, v in fm.items()] + \
               ["---", "", "body"]
        (root / st / ("%s.md" % slug)).write_text("\n".join(body) + "\n",
                                                  encoding="utf-8")
    old = pg.PROG
    pg.PROG = root
    try:
        return pg.Board()
    finally:
        pg.PROG = old


def _check(tickets, strict=False):
    return _board(tickets).check(strict=strict)[1]


def t_cleared_edge_in_blocked_is_a_failure():
    """The measured case: a cleared ticket parked where nothing scans."""
    out = _check([("blocked", "dep", {"track": "N", "prio": 85,
                                      "blocked-by": "[bl]"}),
                  ("done", "bl", {"track": "A", "prio": 50})])
    assert "STALE-EDGE-HIDDEN: dep" in out, out
    assert "invisible to the ranker" in out
    return "a fully-cleared ticket in blocked/ fails the board"


def t_cleared_edge_in_a_ranked_folder_is_not_a_failure():
    """It ranks normally; failing here is crying wolf on 12 of 17 findings."""
    out = _check([("backlog", "dep", {"track": "N", "prio": 55,
                                      "blocked-by": "[bl]"}),
                  ("done", "bl", {"track": "A", "prio": 50})])
    assert "STALE-EDGE-HIDDEN" not in out, out
    return "a cleared edge in backlog/ is not reported as a failure"


def t_cleared_edge_in_a_ranked_folder_is_a_strict_warning():
    """Not a failure is not the same as unreported."""
    out = _check([("backlog", "dep", {"track": "N", "prio": 55,
                                      "blocked-by": "[bl]"}),
                  ("done", "bl", {"track": "A", "prio": 50})], strict=True)
    assert "STALE-EDGE-CLEAR: dep" in out, out
    assert "ranks normally" in out
    return "strict still names it, with why it is harmless"


def t_a_partly_cleared_edge_is_only_a_nudge():
    """Some blockers closing is the normal life of a ticket, not a defect."""
    tk = [("backlog", "dep", {"track": "P", "prio": 60,
                              "blocked-by": "[a, b]"}),
          ("done", "a", {"track": "A", "prio": 50}),
          ("backlog", "b", {"track": "A", "prio": 50})]
    assert "STALE-EDGE" not in _check(tk), "a partial edge failed the board"
    strict = _check(tk, strict=True)
    assert "STALE-EDGE-PARTIAL: dep" in strict, strict
    assert "still waiting on b" in strict
    return "partial staleness is a strict-only nudge"


def t_a_rejected_blocker_can_never_be_satisfied():
    """Zero instances today; silent and permanent when it happens.

    Guards the check that was ALREADY here (`BLOCKED-BY-REJECTED`) and had no
    test. I wrote a second one before finding it — `resolved_slugs` is
    `done | decided`, so a rejected blocker can never be satisfied, which is
    true and was already handled sixty lines further down. The duplicate is
    removed; this guard is what the episode was worth, since two mechanisms
    serving one concept is the smell `normalise-dont-special-case.md` names and
    the second one is the one that stays broken.
    """
    out = _check([("backlog", "dep", {"track": "B", "prio": 45,
                                      "blocked-by": "[bl]"}),
                  ("rejected", "bl", {"track": "A", "prio": 50})])
    assert "BLOCKED-BY-REJECTED: dep" in out, out
    assert "can never become ready" in out
    return "a rejected blocker is reported as permanently unsatisfiable"


def t_a_decided_blocker_counts_as_closed():
    """Parity with resolved_slugs: decided/ satisfies an edge like done/."""
    out = _check([("blocked", "dep", {"track": "N", "prio": 70,
                                      "blocked-by": "[bl]"}),
                  ("decided", "bl", {"track": "U", "prio": 50})])
    assert "STALE-EDGE-HIDDEN: dep" in out, out
    return "decided/ closes an edge exactly as done/ does"


def t_an_open_blocker_is_silent():
    """The check must not fire on a ticket that is genuinely blocked."""
    out = _check([("blocked", "dep", {"track": "N", "prio": 70,
                                      "blocked-by": "[bl]"}),
                  ("backlog", "bl", {"track": "A", "prio": 50})], strict=True)
    assert "STALE-EDGE" not in out, out
    assert "BLOCKER-REJECTED" not in out
    return "a live blocker produces no finding"


def t_the_aperture_note_is_always_printed():
    """Including on a clean board.

    The whole point: a green run must not read as "the family is handled". The
    prose half of this family cannot be scanned for, and three instances of it
    turned up on 2026-08-28 alone.
    """
    out = _check([("backlog", "solo", {"track": "T", "prio": 50})])
    assert "reads FRONTMATTER only" in out, out
    assert "not the family" in out
    return "the scan states its own reach, clean run included"


TESTS = [t_cleared_edge_in_blocked_is_a_failure,
         t_cleared_edge_in_a_ranked_folder_is_not_a_failure,
         t_cleared_edge_in_a_ranked_folder_is_a_strict_warning,
         t_a_partly_cleared_edge_is_only_a_nudge,
         t_a_rejected_blocker_can_never_be_satisfied,
         t_a_decided_blocker_counts_as_closed,
         t_an_open_blocker_is_silent,
         t_the_aperture_note_is_always_printed]


def main():
    rc = 0
    print("stale-edge devtest (%d guards)" % len(TESTS))
    for fn in TESTS:
        try:
            print("  ok   %s — %s" % (fn.__name__, fn()))
        except Exception as e:              # noqa: BLE001 - report, keep going
            rc = 1
            print("  FAIL %s — %s: %s"
                  % (fn.__name__, type(e).__name__, fail_detail(e)))
    print("stale-edge OK" if rc == 0 else "stale-edge BROKEN")
    return rc


if __name__ == "__main__":
    sys.exit(main())
