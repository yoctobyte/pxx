---
slug: bug-a-the-selfhost-rule-is-a-no-op-when-the-seed-is-newer-than-its-sources
track: A
type: bug
prio: 45
status: backlog
blocked-by: []
summary: "`make compiler/pascal26` is described as the one unskippable gate because it IS the byte-identical self-host fixedpoint. In a tree whose seed arrived from outside (a copied-in pinned binary), the seed is newer than the sources, make declares the target up to date, and the rule exits 0 having proved nothing. Caught 2026-08-26 when a full-tier sweep was about to report a verdict for a sha against a binary built from a pin 133 commits older."
---

# The self-host gate silently passes when the seed is newer than the sources

- **Type:** bug (build system) — **Track A** (`Makefile`, the `$(COMPILER)` rule).
  Found by **Track T** while setting up a requested sweep; filed rather than
  fixed, per *T owns the tool, never the bug*, and because a pin decision was
  waiting on the tree at the time.
- **Found:** 2026-08-26.

## What CLAUDE.md promises

> `make compiler/pascal26` stays mandatory, and it is not a test — it is the
> build. It is also, for free, the byte-identical self-host fixedpoint, so it is
> the one thing that cannot be skipped in the name of speed.

That promise holds in the ordinary loop and does not hold in general.

## The failure

A scratch worktree at an arbitrary sha has no self-hosted binary, so the rule
refuses with *"self-hosted compiler seed missing. Run: make bootstrap"*. Seeding
it the obvious way — copying in the tree's own `stable_linux_amd64/default/pinned`
— gives `compiler/pascal26` an mtime **newer than every source file**. The next
invocation prints:

```
seeded from pinned
make: 'compiler/pascal26' is up to date.
```

Make has nothing to do, the recipe never runs, **exit status 0**, and no
`converged after N round(s)` line is emitted because no round happened. The gate
that "cannot be skipped" was skipped by a file timestamp.

## Why it matters, with the case that found it

A full-tier sweep of `e7c0d1d2a` was starting, to gate promoting four Track O
passes from `-O3` to `-O2`. testmgr snapshotted the un-rebuilt binary and began
testing. The pin in that tree is **v226 (`ed8616ac3`)**, which
`git merge-base --is-ancestor` confirms predates `e9317428d`, the first of the
four passes.

So the sweep would have returned a clean verdict, correctly attributed to
`e7c0d1d2a`, **for a compiler that contained none of the work being promoted** —
and a pin and a `master` advance were to rest on it.

The tell was not an error. It was a success message in the wrong dialect: `up to
date` standing where `converged after 1 round(s)` belonged. Everything
downstream was healthy. This is the *incomplete step reporting in the vocabulary
of a complete one* family — the third instance found on 2026-08-26, after the
overwritten differential oracle printing `fpc=[]` and the devtest whose
human-readable note described a constant's provenance as a runtime action.

## Suggested fix (Track A's call)

The rule already tolerates a stale seed by iterating up to `MAX_ROUNDS`. What it
does not do is notice a seed that is *newer* than what it is supposed to be
built from. Options, cheapest first:

1. **Order-only prerequisite / explicit staleness check.** Before trusting the
   target, compare the binary's provenance against the sources rather than their
   mtimes — e.g. refuse when `compiler/pascal26` is newer than every source AND
   no `.selfhost-stamp` records a converged round at this tree state.
2. **A stamp file as the real target.** Make the rule produce
   `compiler/.pascal26.fixedpoint` (recording the converged sha256) and depend on
   that, so a copied-in binary cannot satisfy it.
3. **At minimum, refuse silence.** If the recipe does not run, say which round
   it converged in *last* time, or print that it is trusting an existing binary.
   A gate whose pass and whose skip are the same output is not a gate.

Option 2 is the one that makes the property true rather than usually-true, and
it also gives every consumer a machine-readable answer to *"is this binary a
fixedpoint of these sources?"* — which is the question every sweep, pin and
benchmark actually needs and currently answers by assumption.

## Workaround until then

`touch compiler/*.pas compiler/*.inc` after seeding, and **verify the
`converged after N round(s)` line appears** before trusting the binary. A sweep
or benchmark that cannot show that line has not established its own provenance.

## Related

- `devdocs/dev/gating-and-waiting.md` — hunt async, verify against a known sha.
- The scope note already in CLAUDE.md's claims section: the fixedpoint proves
  self-reproduction **at one optimisation level**. This is a second, independent
  way the same claim can be weaker than it reads.
