#!/usr/bin/env python3
"""Guards for WHICH folders tools/progress.py ranks into `ready` / `next`.

This set drifted silently and nobody noticed for months: `unfinished/` was left
out of ready_tickets() while CLAUDE.md stated twice that it was scanned, so ~23
tickets — including the repo's highest prio (88, an N segfault) and the
html5lib real-world ladder at 65 — were invisible to every dispatch made from
`next`. A truncated queue looks exactly like a healthy one, which is why this
needs a guard rather than a comment.

The set is deliberate in BOTH directions, so both directions are asserted:

  ranked   urgent/, backlog/, backlog_new/, unfinished/
           — unfinished/ is "parked mid-flight; re-claim, do not duplicate".
             Parked is not abandoned; BOARD-brief already tells agents to
             re-claim it, so it must be reachable from the queue that dispatches.

  unranked working/       — a LIVE LOCK. Ranking it dispatches a second agent
                            onto files another agent holds. This one is the
                            reason the set is not simply "everything open".
           blocked/       — unmet blocker by definition (but still resolves AS a
                            blocker target, which is a separate property).
           float/         — Track F parks there, low prio by owner decree.
           experimental/  — X-tagged (R/Z), picked up on request.
           rainy-day/     — someday/maybe.
           done-followup/, decided/, done/, rejected/ — terminal.

Blocker RESOLUTION is orthogonal to ranking and is asserted too: every folder is
LOADED, so a `blocked-by:` naming a ticket parked in unfinished/ or blocked/
resolves to a real ticket (no DANGLING) while still not satisfying the edge.
"""
import pathlib
import sys
import tempfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import progress as P  # noqa: E402

fails = []


def check(cond, what):
    print("  %s %s" % ("ok  " if cond else "FAIL", what))
    if not cond:
        fails.append(what)


print("the ranked set is declared, not scattered")
check(set(P.Board.RANKED_STATUSES) ==
      {"urgent", "backlog", "backlog_new", "unfinished"},
      "RANKED_STATUSES is exactly urgent/backlog/backlog_new/unfinished")
check(all(st in P.STATUSES for st in P.Board.RANKED_STATUSES),
      "every ranked folder is also a loaded folder")

FM = "---\nslug: %s\ntrack: %s\nprio: %d\nblocked-by: [%s]\n---\n\n# %s\n"

with tempfile.TemporaryDirectory() as tmp:
    root = pathlib.Path(tmp)
    old, old_root = P.PROG, P.ROOT
    P.PROG, P.ROOT = root, root       # cmd_next prints paths relative to ROOT
    try:
        for st in P.STATUSES:
            (root / st).mkdir(parents=True)
        # One ticket per folder, all at the same prio, so membership is the only
        # thing that can decide whether it reaches the queue.
        for st in P.STATUSES:
            (root / st / ("bug-b-%s.md" % st)).write_text(
                FM % ("bug-b-" + st, "B", 60, "", st), encoding="utf-8")
        board = P.Board()
        ready = {t.slug for t in board.ready_tickets()}

        print("every ranked folder reaches the queue")
        for st in P.Board.RANKED_STATUSES:
            check("bug-b-" + st in ready, "%s/ is ranked" % st)

        print("every other folder stays out — each for its own reason")
        for st in P.STATUSES:
            if st in P.Board.RANKED_STATUSES:
                continue
            check("bug-b-" + st not in ready, "%s/ is NOT ranked" % st)

        print("a parked ticket can win, and says it is a re-claim when it does")
        # urgent/ always sorts first by design, so drop the urgent fixture:
        # what is under test is prio, not the urgent override.
        (root / "urgent" / "bug-b-urgent.md").unlink()
        (root / "unfinished" / "bug-n-parked-top.md").write_text(
            FM % ("bug-n-parked-top", "N", 88, "", "parked"), encoding="utf-8")
        b2 = P.Board()
        check(b2.ready_tickets()[0].slug == "bug-n-parked-top",
              "the highest-prio ticket wins next even though it is parked")
        check("re-claim" in b2.cmd_next(),
              "next says PARKED/re-claim rather than reading as fresh work")
        check("re-claim" in b2.cmd_ready(),
              "ready flags the parked rows too")
        check("bug-n-parked-top" in b2.cmd_ready("N"),
              "--track still filters a parked ticket normally")

        print("ranking and blocker RESOLUTION are separate properties")
        (root / "backlog" / "bug-b-waits-on-parked.md").write_text(
            FM % ("bug-b-waits-on-parked", "B", 70, "bug-b-unfinished", "waits"),
            encoding="utf-8")
        (root / "backlog" / "bug-b-waits-on-blocked.md").write_text(
            FM % ("bug-b-waits-on-blocked", "B", 70, "bug-b-blocked", "waits"),
            encoding="utf-8")
        b3 = P.Board()
        check("bug-b-unfinished" in b3.by_slug and "bug-b-blocked" in b3.by_slug,
              "a blocker parked in unfinished//blocked/ resolves to a real ticket")
        r3 = {t.slug for t in b3.ready_tickets()}
        check("bug-b-waits-on-parked" not in r3,
              "...but an unfinished blocker does NOT satisfy the edge")
        check("bug-b-waits-on-blocked" not in r3,
              "...nor does a blocked one")
        check(b3.effective_prio()["bug-b-unfinished"] == 70,
              "an unfinished blocker still inherits its dependent's priority")
    finally:
        P.PROG, P.ROOT = old, old_root

print()
if fails:
    print("FAILED %d check(s):" % len(fails))
    for f in fails:
        print("  - " + f)
    sys.exit(1)
print("all ranked-status guards green")
