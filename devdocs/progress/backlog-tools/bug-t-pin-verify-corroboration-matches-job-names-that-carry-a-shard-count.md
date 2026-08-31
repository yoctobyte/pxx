---
track: T
prio: 30
type: bug
blocked-by: []
summary: "twatch.py's pin_verify_corroboration() decides whether a pin-verify RED is corroborated by matching job names LITERALLY, and a shard count lives inside the name (`test-pascal-conformance#shard5/6`). Resplit that suite to 8 shards and every match fails: the caveat silently degrades to `the full tier reported on none of those -- still a single run`, which is the uncorroborated verdict. No error, no diff, correct about something else. Latent, not firing today; the trigger is a shard-count change, which is a routine thing to do."
---

# The corroboration check is keyed on a name that embeds a shard count

Found 2026-08-31 by frankT while annotating the v398 pin verify, and surfaced
rather than fixed — the session stood down before it could be taken.

`pin_verify_corroboration()` answers "did a later, broader run also see these
reds?" by looking each pin-verify job name up in seven's jobs map. Job names for
sharded suites carry the shard count in the name itself:

```
test-pascal-conformance#shard5/6
```

A resplit to 8 shards changes every one of those names. The lookup then misses
for all of them, and the function reports the same thing it would report if the
full tier genuinely had not covered them — *"the full tier reported on none of
those — still a single run"*. That is the uncorroborated verdict, produced by a
key mismatch rather than by evidence.

**This is the guard-that-cannot-fail family, in its quieter form:** the guard can
still fail, but its failure mode is indistinguishable from its "no corroboration"
success mode, so the degradation is invisible from the outside. It needs a
**positive control** — a case that MUST come back corroborated, asserted — which
is what would catch a total key mismatch.

## Why it is worth fixing rather than watching

The mitigation that already landed (b6454696b) is a *stored* note in
`seven.json`'s `pin_verify.note`, written by re-deriving the claim and refusing
to store it if either underlying fact fails. `--status` prints the stored note
before the computed lines, and prints it **even when they agree**, so a future
divergence between stored and computed is visible instead of deduplicated away.

That makes the failure *detectable by a reader who looks*. It does not make the
computed path correct, and the computed path is the one that runs on every
`--status` call for every verify that has no stored note.

## Two things worth keeping from how it was found

1. **A durable annotation must not embed a decaying number.** The note
   deliberately names the pinned sha and lets the reader compute the distance,
   rather than storing "99 testable commits behind" — true for about 45 seconds
   in this repo. An annotation that goes false on its own is the failure being
   prevented, not a small version of it.
2. **`--status` reads tstate out of a git ref, not the worktree.** A first check
   showed no NOTE line and was answering correctly about the committed tree.
   Free positive control from real data: plexus's v393 verify has no `note` and
   renders no NOTE line, v398 renders both — so "the renderer works" was
   asserted against a case that must show nothing, not only against the case
   that must show something.
