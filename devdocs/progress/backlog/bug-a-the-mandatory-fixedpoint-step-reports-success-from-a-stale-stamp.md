---
track: A
prio: 60
type: bug
status: new
found: 2026-08-31
found-by: frankB
owner: ""
blocked-by: []
summary: "`make compiler/pascal26` prints `self-host fixedpoint: verified — 2 round(s), <sha>` and exits 0 WITHOUT REBUILDING whenever a CONSISTENT binary+stamp pair carries an mtime newer than the sources. Reproduced deliberately, twice independently (frankB and frank-coordinator): plant f92c42a69850 plus a stamp naming it, touch both, run make against a tree whose real fixedpoint is 3d5308a75742 — success line, round count, sha, binary unchanged. THE DEFECT IS THAT THE REPLAY LINE IS CONFUSABLE WITH A RESULT, NOT THAT THE CHECK IS INADEQUATE: a genuine build prints `converged after N round(s)` AND `verified — N`, a replay prints only `verified`, so CLAUDE.md's existing rule (do not accept the build until you have seen `converged after N round(s)`) CATCHES THIS CLEANLY and is not defeated — two agents simply pattern-matched on the `verified` line instead of following it. Fix is small: make the replay line not look like a result. The round count is a stored stamp field and cannot separate a replay from a build. Sibling: bug-t-the-gate-checks-binary-freshness-with-a-heuristic-that-cannot-see-the-common-case."
---

# The mandatory fixedpoint step reports success from a stale stamp

## Repro (deliberate, ~15s)

Tree at `c2545bd6a`, whose true fixedpoint is `3d5308a75742`:

```sh
cp <pre-change binary> compiler/pascal26                    # f92c42a69850
printf 'rounds 2\nsha256 f92c42a69850...\n' > compiler/.pascal26.fixedpoint
touch compiler/pascal26 compiler/.pascal26.fixedpoint       # newer than sources
make compiler/pascal26
```

```
self-host fixedpoint: verified — 2 round(s), f92c42a69850
```

Binary afterwards: **`f92c42a69850`, unchanged** — the fixedpoint of sources
that are no longer on disk. Exit 0.

## Why the existing guards do not catch it

`Makefile:307` compares the binary's sha against the stamp's and refuses on a
mismatch — that guard is real and it fires (verified: planting a binary
*without* updating the stamp is refused loudly). It cannot fire here, because
the pair is internally **consistent**; both simply describe older sources.
`$(COMPILER_STAMP)` is an ordinary file prerequisite, so a stamp newer than the
sources means the fixedpoint recipe never runs, and the `$(COMPILER)` rule then
finds sha == stamp and does nothing.

**And the round count cannot be used to detect it.** `rounds 2` is a stored
field in the stamp; `verified — N round(s)` reads it back. A replay prints a
round count exactly like a build. (This defeated one agent's reasoning
explicitly, mine — "two rounds means the iteration ran" is false.)

## The guidance is NOT defeated — we failed to follow it

**Corrected 2026-08-31, same day, before anyone acted on it.** This ticket first
claimed the defect "defeats" CLAUDE.md's instruction and that "the current
guidance would pass it." **That is false**, and leaving it would have invited
someone to weaken the one rule that actually works here. Diffing the two
outputs:

```
GENUINE build:    converged after 2 round(s)
                  self-host fixedpoint: verified — 2 round(s), 3d5308a75742

REPLAY (planted): self-host fixedpoint: verified — 2 round(s), f92c42a69850
```

**The replay prints no `converged` line at all.** CLAUDE.md says *do not accept
the build until you have seen `converged after N round(s)`*, and grepping for
`converged` exactly as instructed catches this cleanly. The rule is sound; two
agents (including this ticket's author) read `verified — N round(s)` as
satisfying it because it was close enough in shape.

So the defect is **the replay line is confusable with a result** — it carries a
sha and a round count in the same sentence shape as success — not that the check
is inadequate. That framing makes the fix small and keeps the existing rule
intact.

Reached in the wild by three agents on 2026-08-31 by three different routes
(a sibling's `compiler/**` pulled without rebuilding; a pull mid-gate; a
`git stash` that reverts sources and leaves the binary built with the diff).
All three produced a RED gate that read as a miscompile on master; none was.

## The cheap tell, until it is fixed

- `converged after N round(s)` — the iteration RAN. A result.
- `verified — N round(s), <sha>` — read back from the stamp. A report.

A genuine build prints **both**, `converged` first. `verified` alone means
nothing was rebuilt. Not a fix; a thing to look for.

## Suggested fix

**First and smallest: make the replay line unmistakable.** Something like
`self-host fixedpoint: stamp says f92c42a69850 (NOT rebuilt)` cannot be mistaken
for a result, and the existing `converged` rule keeps working unchanged. This
alone would have prevented all three of tonight's incidents.

Then, for the underlying cause:
make the stamp's validity depend on the SOURCES rather than on mtime ordering —
e.g. record a hash of `$(COMPILER_SRC) $(COMPILER_INC)` in the stamp and re-run
the iteration when it differs. The Makefile comment above `selfhost-verify`
already argues **"mtime is not provenance and that is the whole bug"** and
addresses it with a `.PHONY` prerequisite so the *sha check* always runs; the
gap is that the sha check validates the pair against itself, never against the
sources. Same sentence, one level further.

## Positive control for whatever fix lands

The repro above MUST fail after the fix: a consistent stale pair with newer
mtimes must trigger a rebuild to `3d5308a75742`, not a `verified` line. And the
honest-build arm must stay green — deleting the stamp and rebuilding gives
`converged after 1 round(s)` → `3d5308a75742`.
