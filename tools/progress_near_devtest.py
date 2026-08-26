#!/usr/bin/env python3
"""Devtest for progress.py's near-neighbour search — `near` and `dupes`.

Guards the CALIBRATION, which is the part of this feature that can rot without
anyone noticing: the commands keep printing plausible-looking rows while the
metric silently stops separating a real duplicate from an ordinary pair.

Three metrics were measured against the pair that prompted the feature before
one was chosen, and two of them fail in ways that are invisible from the output:

  * Jaccard ranks ticket-vs-ticket fine and scores a filer's six-word TITLE
    below 0.03 against every ticket on the board.
  * Containment fixes that and inverts it: a long ticket trivially contains a
    short query, so a title about a Variant shift scored 0.86 against
    `feature-dwarf-debug-info` for sharing the words "static", "arithmetic" and
    "logical".

The cases below pin the properties those two failed, not the exact numbers:
scores drift as the board grows, orderings do not.
bug-the-queue-makes-filing-a-duplicate-the-path-of-least-resistance

No repo state touched: reads the live board, writes nothing.
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import progress  # noqa: E402

FAILS = []


def check(name, ok, detail=""):
    print(("  PASS  " if ok else "  FAIL  ") + name + (("  — " + detail) if detail and not ok else ""))
    if not ok:
        FAILS.append(name)


def main() -> int:
    board = progress.Board()
    heads = {t.slug: progress._tokens(progress._ticket_head(t)) for t in board.tickets}
    full = {t.slug: progress._tokens(progress._ticket_doc(t)) for t in board.tickets}
    sh = progress.Similarity(heads)
    sf = progress.Similarity(full)

    # The known duplicate pair: two agents, four days apart, one defect.
    A = "feature-t-gate-quick-should-smoke-the-pinned-compiler"
    B = "bug-t-gate-quick-cannot-see-a-broken-pinned-rtl"
    have_pair = A in board.by_slug and B in board.by_slug
    check("the known duplicate pair is still on the board", have_pair,
          "resolved tickets are still loaded, so this should not go missing")

    if have_pair:
        dup = sf.score(full[A], full[B])
        opens = [t for t in board.tickets if t.status in progress.OPEN_STATUSES]
        # A sample is enough and keeps the devtest fast; the median of a few
        # thousand pairs is stable.
        sample = []
        for i in range(0, min(len(opens), 90)):
            for j in range(i + 1, min(len(opens), 90)):
                sample.append(sf.score(full[opens[i].slug], full[opens[j].slug]))
        sample.sort()
        median = sample[len(sample) // 2] if sample else 0.0
        check("a known duplicate outscores the median open pair by 2x or more",
              dup >= 2 * median and dup > 0.15,
              "dup=%.3f median=%.3f" % (dup, median))

    # A filer's TITLE must reach its own ticket. Ticket-length bias is what
    # containment got wrong; this is the case that caught it.
    probes = [t for t in board.tickets if t.status in progress.OPEN_STATUSES][:25]
    worst = None
    for t in probes:
        title = t.fm.get("title", "") or t.slug.replace("-", " ")
        q = progress._tokens(title)
        if len(q) < 3:
            continue
        rows = sorted(((sh.score(q, heads[o.slug]), o.slug) for o in probes), reverse=True)
        rank = [s for _, s in rows].index(t.slug)
        if worst is None or rank > worst[0]:
            worst = (rank, t.slug)
    check("a ticket's own title ranks it first among its neighbours",
          worst is not None and worst[0] == 0,
          "worst rank %s for %s" % (worst if worst else ("n/a", "n/a")))

    # Length bias: a short query must not saturate against a long ticket merely
    # for sharing common words. Compare a deliberately unrelated title against
    # the LONGEST open ticket.
    longest = max((t for t in board.tickets if t.status in progress.OPEN_STATUSES),
                  key=lambda t: len(full[t.slug]))
    q = progress._tokens("a variant shr is arithmetic where the static shr is logical")
    check("a short unrelated query does not saturate against the longest ticket",
          sh.score(q, heads[longest.slug]) < 0.5,
          "%.3f against %s (%d tokens)" % (sh.score(q, heads[longest.slug]),
                                           longest.slug, len(full[longest.slug])))

    # Self-similarity is 1 and the metric is symmetric — cheap, and both were
    # briefly false while the denominator was being changed.
    any_slug = next(iter(heads))
    check("score is 1.0 against itself", abs(sh.score(heads[any_slug], heads[any_slug]) - 1.0) < 1e-9)
    s1, s2 = list(heads.values())[:2]
    check("score is symmetric", abs(sh.score(s1, s2) - sh.score(s2, s1)) < 1e-9)

    # An empty query answers 0 rather than dividing by nothing.
    check("an empty query scores 0", sh.score(set(), s1) == 0.0)

    print()
    if FAILS:
        print("progress-near-devtest: %d FAILURE(S): %s" % (len(FAILS), ", ".join(FAILS)))
        return 1
    print("progress-near-devtest: ALL OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
