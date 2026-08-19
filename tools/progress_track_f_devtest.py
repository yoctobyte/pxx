#!/usr/bin/env python3
"""Guards for Track F in tools/progress.py.

Track F (floating point) is a WORK-TAG, not a file-lane: an F ticket also carries
the lane that owns its files (`track: B+F`), parks in `devdocs/progress/float/`,
and is never ranked. Three separate things have to hold for that to be true, and
each of them was broken or absent before 2026-08-19:

  1. `B+F` must SURVIVE normalization. F was missing from both character classes
     in normalize_track(), so `track: B+F` reduced to `"B+"`, failed the strict
     fullmatch, and returned `""` — the ticket matched NEITHER --track B nor
     --track F. The substring test in track_matches() was never the problem.
  2. Membership of float/ must supply the F, and must APPEND it rather than
     replace the owning lane — a work-tag that eats the file-ownership letter is
     worse than no tag, because collision rules read that letter.
  3. Nothing in float/ may rank: not itself (ready/next), and not anything ELSE
     (a parked ticket must not lend leverage to its blocker).

Plus the negative that the charter cares about most: F is NOT auto-tagged from a
slug or from prose. "Rank the mechanism, never the datatype" — a bug that merely
lives in float code stays an ordinary bug in its own lane, and every cheap
textual signal for float keys on the datatype. The folder is the only trigger.
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


def ticket(status, slug, track="", blockers=(), prio=50):
    fm = {"prio": str(prio)}
    if track:
        fm["track"] = track
    text = "---\n---\n\n# %s\n" % slug
    return P.Ticket(pathlib.Path("/nonexistent/%s/%s.md" % (status, slug)),
                    status, slug, text, fm, list(blockers))


print("normalize_track keeps F (the bug that made every other piece moot)")
check(P.normalize_track("B+F") == "B+F", "B+F normalizes to itself, not ''")
check(P.normalize_track("P+F") == "P+F", "P+F survives")
check(P.normalize_track("A+F") == "A+F", "A+F survives")
check(P.normalize_track("b/f") == "B+F", "lowercase and / spellings survive")
check(P.normalize_track("F") == "F", "a bare F is a valid track")
check(P.normalize_track("Q+F") == "", "an unknown letter still rejects the whole value")

print("float/ supplies F, and never at the expense of the owning lane")
check(ticket("float", "bug-b-rounding-api-gaps", "B").track == "B+F",
      "a float/ ticket declaring B surfaces as B+F")
check(ticket("float", "bug-n-complex-magnitude", "N").track == "N+F",
      "...and one declaring N as N+F")
check(ticket("float", "bug-b-already-tagged", "B+F").track == "B+F",
      "a hand-written B+F is not doubled")
check(ticket("float", "meta-float-accuracy-policy", "U").track == "U+F",
      "the policy ticket keeps U")

print("rank the mechanism, never the datatype: no slug or prose arm")
check(ticket("backlog", "bug-b-writefloat-truncates-at-1e15", "B").track == "B",
      "a float-named ticket in backlog/ is NOT auto-tagged F")
check(ticket("backlog", "feature-opt-float-register-temporaries", "").track != "O+F",
      "nor is a float-named opt ticket")
t = ticket("backlog", "bug-a-segfault", "A")
t.text += "\nFound while chasing a Track F ulp difference.\n"
check(t.track == "A", "a prose mention of Track F does not move a Track A bug")

print("--track F is a real filter, and it is a substring test on the combo")
b = P.Board.__new__(P.Board)
check(b.track_matches("B+F", "F") and b.track_matches("B+F", "B"),
      "B+F answers to both --track B and --track F")
check(not b.track_matches("B", "F"), "...and a plain B does not answer to F")
args = P.parse_args(["ready", "--track", "F"])
check(args.track == "F", "--track F is an accepted choice")

print("nothing in float/ ranks — not itself, not anything else")
check("float" in P.STATUSES, "float/ is loaded (board, check, blocker resolution see it)")
with tempfile.TemporaryDirectory() as tmp:
    root = pathlib.Path(tmp)
    old, old_root = P.PROG, P.ROOT
    P.PROG, P.ROOT = root, root   # cmd_next prints paths relative to ROOT
    try:
        for st in P.STATUSES:
            (root / st).mkdir(parents=True)
        fm = "---\nslug: %s\ntrack: %s\nprio: %d\nstatus: %s\nblocked-by: [%s]\n---\n\n# %s\n"
        (root / "backlog" / "bug-b-plain.md").write_text(
            fm % ("bug-b-plain", "B", 50, "backlog", "", "plain"), encoding="utf-8")
        (root / "backlog" / "bug-b-blocker.md").write_text(
            fm % ("bug-b-blocker", "B", 50, "backlog", "", "blocker"), encoding="utf-8")
        (root / "float" / "bug-b-parked.md").write_text(
            fm % ("bug-b-parked", "B", 99, "float", "bug-b-blocker", "parked"),
            encoding="utf-8")
        board = P.Board()
        ready = [t.slug for t in board.ready_tickets()]
        check("bug-b-parked" not in ready,
              "a parked F ticket at prio 99 is not ready (ready reads backlog/urgent only)")
        check("bug-b-parked" not in board.cmd_next(),
              "...and never wins next")
        check("no ready ticket for Track F" in board.cmd_next("F"),
              "next --track F says so rather than reaching into float/")
        check(board.by_slug["bug-b-parked"].track == "B+F",
              "the parked ticket still reads as B+F on the board")
        check(board.leverage_counts().get("bug-b-blocker", 0) == 0,
              "a parked F ticket lends NO leverage to what blocks it")
        check(board.effective_prio()["bug-b-blocker"] == 50,
              "...and lends it NO priority either (prio 99 parked, blocker stays 50)")
        (root / "backlog" / "bug-b-active.md").write_text(
            fm % ("bug-b-active", "B", 50, "backlog", "bug-b-blocker", "active"),
            encoding="utf-8")
        b2 = P.Board()
        check(b2.leverage_counts().get("bug-b-blocker", 0) == 1,
              "...while an ACTIVE dependent still does")
        (root / "float" / "bug-b-parked.md").write_text(
            fm % ("bug-b-parked", "B", 10, "float", "bug-b-blocker", "parked"),
            encoding="utf-8")
        (root / "backlog" / "bug-b-active.md").write_text(
            fm % ("bug-b-active", "B", 80, "backlog", "bug-b-parked", "active"),
            encoding="utf-8")
        check(P.Board().effective_prio()["bug-b-parked"] == 80,
              "a float ticket DOES inherit from an active dependent — that is the "
              "un-park signal, and it is the direction that does not rank anything")
    finally:
        P.PROG, P.ROOT = old, old_root

print()
if fails:
    print("FAILED %d check(s):" % len(fails))
    for f in fails:
        print("  - " + f)
    sys.exit(1)
print("all Track F guards green")
