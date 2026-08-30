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

    # ---- the two calibration properties, each stated as a NUMBER ----
    #
    # Rewritten 2026-08-30 after measuring what the previous pair actually
    # discriminated. Both were misattributed, and one was vacuous:
    #
    #   * "a ticket's own title ranks it first" never scored a TITLE. Zero of
    #     the 25 probes carry a `title:` field, so the `or` fallback was the
    #     only branch ever taken and the query was always a slug. It also
    #     rejected the wrong metric: measured, containment ranks every probe
    #     FIRST (worst rank 0) and passes it, while the metric in use scores 1
    #     — the assertion had gone red because a sibling was filed
    #     (`feature-pascal-corpus-oop` shares three of four slug words with
    #     `feature-pascal-corpus-expansion` and is a legitimately better match
    #     for them), not because anything regressed.
    #
    #   * "does not saturate against the longest ticket" picked `longest` by
    #     `len(full[...])` and then scored `heads[longest]` — an 11-token head
    #     of a 6812-token document. The query shared ZERO tokens with that head,
    #     so it scored 0.000 under all three metrics including the one it exists
    #     to reject. A guard that cannot fail is not a guard.
    #
    # What the two rejected metrics actually do, measured on this board:
    #
    #   metric        min self-score   saturation vs the longest DOC
    #   Similarity        0.148              0.021
    #   Jaccard           0.028              0.001     <- fails the floor
    #   Containment       1.000              1.000     <- fails saturation
    #
    # So: a FLOOR on the self-score rejects Jaccard (its collapse on short
    # queries is the documented failure), and saturation against the full DOC
    # rejects containment. Neither flips when a sibling ticket is filed, which
    # is what made the rank test brittle.
    probes = [t for t in board.tickets if t.status in progress.OPEN_STATUSES][:25]
    longest = max((t for t in board.tickets if t.status in progress.OPEN_STATUSES),
                  key=lambda t: len(full[t.slug]))
    q_unrelated = progress._tokens(
        "a variant shr is arithmetic where the static shr is logical")

    def self_floor(index, metric):
        """Lowest score a probe's own slug gets against its own head."""
        worst = None
        for t in probes:
            q = progress._tokens(t.slug.replace("-", " "))
            if len(q) < 3:
                continue
            sc = metric.score(q, index[t.slug])
            if worst is None or sc < worst[0]:
                worst = (sc, t.slug)
        return worst

    def saturation(metric_full):
        """A short unrelated query against the longest DOCUMENT — full, not
        head, or the comparison is against a ticket that is not long."""
        return metric_full.score(q_unrelated, full[longest.slug])

    floor = self_floor(heads, sh)
    check("a slug reaches its own ticket with a usable score",
          floor is not None and floor[0] >= 0.10,
          "worst %.3f for %s" % floor if floor else "n/a")
    sat = saturation(sf)
    check("a short unrelated query does not saturate against the longest doc",
          sat < 0.5,
          "%.3f against %s (%d tokens)" % (sat, longest.slug, len(full[longest.slug])))

    # POSITIVE CONTROL. Both properties above are numbers measured on live board
    # data, so both can drift into being unfailable — which is exactly what
    # happened to the guard this replaces, silently, for as long as it existed.
    # Re-running the two REJECTED metrics through the same code proves the
    # checks still discriminate. If either control stops failing, the guard
    # above it has stopped guarding, whatever it prints.
    class _Containment:
        def __init__(self, index): pass
        def score(self, q, d): return (len(q & d) / len(q)) if q else 0.0

    class _Jaccard:
        def __init__(self, index): pass
        def score(self, q, d): return (len(q & d) / len(q | d)) if (q | d) else 0.0

    j_floor = self_floor(heads, _Jaccard(heads))
    check("CONTROL: Jaccard still fails the self-score floor",
          j_floor is not None and j_floor[0] < 0.10,
          "Jaccard floor %.3f — the floor no longer rejects it" % (j_floor[0] if j_floor else -1))
    check("CONTROL: containment still fails the saturation check",
          saturation(_Containment(full)) >= 0.5,
          "containment saturation %.3f — the check no longer rejects it"
          % saturation(_Containment(full)))

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
