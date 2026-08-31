---
slug: decide-two-threading-docs-disagreed-for-seven-weeks
track: U
prio: 40
status: open
---

# Two threading docs, one subject: consolidate, or make the split explicit?

`devdocs/dev/threading.md` and `devdocs/dev/threading-model.md` overlap enough
that a reader who finds one has no reason to look for the other. **They disagreed
for seven weeks.** frankD fixed the `--threadsafe is x86-64 only` claim in one of
them on 2026-08-30 and did not look in the other, because nothing about "the
threading doc" suggests there are two — then found three more instances of the
same false claim in the sibling an hour later, via an unrelated grep.

This is filed as a DECISION and not an audit finding on frankD's own reasoning,
which is right: **it cannot be fixed by editing either document.** Merging them is
a judgement about what the docs are *for*, and a lane merging two live references
on its own initiative is exactly the call that should not be unilateral.

Direct precedent: `decide-two-devdocs-directories-make-a-wrong-grep-look-like-a-refutation`
— same shape, one level up. Two places to look means every non-existence claim
made by grepping one of them is unsound, and nothing in the output says so.

## The fork

1. **Merge into one** — one file, one subject, one place a wrong claim can live.
   Costs the distinction the two files were presumably created to draw, and
   whatever inbound links exist.
2. **Keep both, with a stated division of labour** — each opens with what it
   covers and what the *other* covers, so finding one leads to the other. Cheaper,
   preserves the split, and relies on a header nobody is obliged to maintain.
3. **Keep both, no change** — the status quo that produced the seven weeks.

## Recommendation

**(1) merge**, unless the split has a purpose a reader can state. The evidence
that the split does not carry its own weight is that it silently produced
contradictory claims on the flagship question of the subject — and option 2's
cross-reference header is itself a stated limit with a mechanism, i.e. exactly the
artefact faces 109/113 say rots without anyone noticing.

Whoever decides: this is a Track D file-lane change once decided (prose only, no
`compiler/**`, no `lib/**`), so it re-files into D as ordinary work.

## Provenance

frankD, 2026-08-30, while sweeping for face-109 candidates. The stale claim that
exposed the split is written up as faces 113 and 114 in
`feature-a-a-refusal-is-a-claim-with-a-date-on-it`.
