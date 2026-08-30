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


def _fixture(tickets):
    """A throwaway progress tree. `tickets` is (status, slug, fm)."""
    root = Path(tempfile.mkdtemp(prefix="stale-edge-"))
    for st in pg.STATUSES:
        (root / st).mkdir(parents=True, exist_ok=True)
    for st, slug, fm in tickets:
        body = ["---"] + ["%s: %s" % (k, v) for k, v in fm.items()] + \
               ["---", "", "body"]
        (root / st / ("%s.md" % slug)).write_text("\n".join(body) + "\n",
                                                  encoding="utf-8")
    return root


def _render_boards(root):
    """Write the fixture's own BOARD*.md, rendered from its own tickets.

    A CLEAN board has to actually BE clean. check() compares each BOARD file
    against what it would render right now -- absent is NO-BOARD, different is
    STALE-BOARD -- so a fixture with no boards, or with placeholder boards,
    carries three findings and is not the state the clean-run guard below is
    named for. Rendering them from the fixture's own Board is the only way to
    satisfy a check that regenerates and compares.
    """
    old = pg.PROG
    pg.PROG = root
    try:
        b = pg.Board()
        (root / "BOARD.md").write_text(b.render_board_md(), encoding="utf-8")
        (root / "BOARD-brief.md").write_text(b.render_brief_md(),
                                             encoding="utf-8")
        for st in pg.ARCHIVED_STATUSES:
            (root / ("BOARD-%s.md" % st)).write_text(b.render_archive_md(st),
                                                     encoding="utf-8")
    finally:
        pg.PROG = old


def _check(tickets, strict=False):
    """Board.check() over `tickets` alone — PROG held for the WHOLE call.

    THE FIXTURE USED TO LEAK, and it leaked in the way that is hardest to see:
    it swapped `pg.PROG` to the throwaway tree, built the Board, and restored
    PROG in a `finally` -- then called `.check()` outside the swap. Board()
    captures its tickets at construction, so every assertion keyed on
    `self.by_status` kept passing; but `check()` ALSO walks `PROG / st` on the
    filesystem at call time, for the DUP-SLUG / NO-FRONTMATTER / NEAR-DUP
    scans. Half of check() saw the fixture and half saw the live repo.

    It stayed invisible for as long as the live repo happened to be clean.
    The moment two real backlog tickets shared four slug words, a NEAR-DUP
    about `decide-posix-master-vs-fpc-named-master-for-the-socket-facades` --
    a ticket this devtest has nothing to do with -- landed in `out` and failed
    the only guard that asserts on a CLEAN board. `tools-devtest#00` went red
    on it (regression-tools-devtest-00-3) and the ticket read as a stale-edge
    regression.

    Same shape as the harness that deleted the pin it was measuring: a
    `finally` that restores state before the thing under test has run. So the
    swap now spans the call, and `_board()` is gone rather than left as a
    second entry point that could be used the old way again.
    """
    root = _fixture(tickets)
    _render_boards(root)
    old = pg.PROG
    pg.PROG = root
    try:
        return pg.Board().check(strict=strict)[1]
    finally:
        pg.PROG = old


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
    # KEYED ON THE NOTE'S IDENTITY AND ITS TWO CLAIMS, not on its wording.
    # This asserted the literal "reads FRONTMATTER only" -- and 65a63f0d2
    # rewrote the sentence to "reads FRONTMATTER; STALE-PARK reads PROSE ..."
    # when it added the prose half, leaving the assertion behind. The guard has
    # been red ever since, and it is what reddened tools-devtest#00
    # (regression-tools-devtest-00-3). Proof rather than inference: the exact
    # string is present in progress.py at 65a63f0d2~1 and absent at 65a63f0d2.
    #
    # A guard whose subject is "the scan states its own reach" should not be
    # able to fail because the reach got WIDER and was described more
    # precisely. So it now asserts what must be true of any wording: the note
    # is emitted, it names the aperture it reads, and it disclaims the family.
    # That is not a loosened tolerance -- delete the note and all three fail.
    #
    # SECOND TIME, 2026-08-30. The rewrite above still keyed the note's
    # EXISTENCE on its opening words -- `NOTE stale-edge` -- and the opening was
    # later rewritten to `NOTE a STALE-PARK hit matches SLUGS...`. Red again,
    # for the same reason, one clause to the left: the two claims were made
    # wording-independent and the identity was not. A guard that says "do not
    # key on wording" and then keys on wording is worth more as a lesson than
    # as a third rewrite, so the identity test is now structural -- SOME line
    # opens with NOTE, and the note names the aperture it is about. Delete the
    # note and all four still fail.
    note = next((ln for ln in out.splitlines() if ln.startswith("NOTE ")), None)
    assert note is not None, out
    assert "stale-edge" in note or "STALE-PARK" in note, note
    assert "FRONTMATTER" in out, out
    assert "not the family" in out, out
    return "the scan states its own reach, clean run included"


def t_the_filesystem_scan_sees_the_fixture_not_the_live_repo():
    """check() walks PROG on disk as well as reading self.by_status.

    THIS GUARD EXISTS BECAUSE ITS ABSENCE WAS NEARLY SHIPPED. The old fixture
    restored `pg.PROG` before calling `.check()`, so the DUP-SLUG /
    NO-FRONTMATTER / NEAR-DUP half of check() scanned the LIVE REPO while every
    other assertion read the fixture. That was caught only by accident -- the
    aperture guard's assertion had ALSO drifted, so it failed and dumped `out`,
    which happened to contain a NEAR-DUP about two real backlog tickets. Repair
    the wording and the leak becomes silent again: with the leak reinstated and
    the wording fixed, this file reported OK. Measured, not assumed.

    So the isolation is asserted directly and in a way the live repo cannot
    satisfy or defeat:

      * POSITIVE -- a synthetic near-duplicate pair in the fixture IS reported,
        which proves the scan reaches the fixture at all (without this the
        negative below is satisfied by a scan that reads nothing);
      * NEGATIVE -- on a clean fixture, no finding names any file that is not
        in the fixture. State-independent: it holds whether or not the live
        repo currently carries near-duplicates of its own, and today it does
        carry six.
    """
    out = _check([("backlog", "zz-fixture-alpha-beta-gamma-delta",
                   {"track": "T", "prio": 50}),
                  ("backlog", "zz-fixture-alpha-beta-gamma-epsilon",
                   {"track": "T", "prio": 50})])
    assert "NEAR-DUP" in out and "zz-fixture-alpha-beta-gamma-delta" in out, out

    out = _check([("backlog", "solo", {"track": "T", "prio": 50})])
    stray = [ln for ln in out.splitlines()
             if ".md" in ln and "solo.md" not in ln
             and not ln.startswith(("NOTE", "NO-BOARD", "STALE-BOARD"))]
    assert not stray, "check() reported about files outside the fixture:\n" + \
        "\n".join(stray)
    return "the on-disk scan is confined to the fixture"


TESTS = [t_cleared_edge_in_blocked_is_a_failure,
         t_cleared_edge_in_a_ranked_folder_is_not_a_failure,
         t_cleared_edge_in_a_ranked_folder_is_a_strict_warning,
         t_a_partly_cleared_edge_is_only_a_nudge,
         t_a_rejected_blocker_can_never_be_satisfied,
         t_a_decided_blocker_counts_as_closed,
         t_an_open_blocker_is_silent,
         t_the_aperture_note_is_always_printed,
         t_the_filesystem_scan_sees_the_fixture_not_the_live_repo]


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
