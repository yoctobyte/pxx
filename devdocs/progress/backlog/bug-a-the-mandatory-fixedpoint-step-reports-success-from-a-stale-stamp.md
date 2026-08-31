---
track: A
prio: 60
type: bug
status: new
found: 2026-08-31
found-by: frankB
owner: ""
blocked-by: []
summary: "`make compiler/pascal26` — the one step CLAUDE.md calls mandatory and calls the fixedpoint — prints `self-host fixedpoint: verified — 2 round(s), <sha>` and exits 0 WITHOUT REBUILDING, whenever a consistent binary+stamp pair carries an mtime newer than the sources. Reproduced deliberately: planted f92c42a69850 (the pre-d782926ce fixedpoint) plus a stamp naming it, touched both, ran make against a tree whose real fixedpoint is 3d5308a75742 — success line, round count, sha, binary unchanged. The round count is a STORED FIELD in compiler/.pascal26.fixedpoint, not a count of work done, so it cannot distinguish a replay from a build. This defeats CLAUDE.md's own instruction for the documented sibling case ('grep for converged, not for a zero exit'): there is no `converged` line to miss and the line that IS printed looks like success. Reached in the wild by three agents in one night via three routes; the cheap tell is the VERB — `converged after N` is a result, `verified — N` is a replay of stored state."
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

## Why it matters more than the documented sibling

CLAUDE.md already documents the `cp`-a-seed variant, which prints
`make: 'compiler/pascal26' is up to date`, and instructs: **"grep the tree for
`converged`, not for a zero exit"**. That instruction *passes this variant* —
the output contains a success sentence, a round count and a sha, and no
`converged` line to notice missing.

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

Make the stamp's validity depend on the SOURCES rather than on mtime ordering —
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
