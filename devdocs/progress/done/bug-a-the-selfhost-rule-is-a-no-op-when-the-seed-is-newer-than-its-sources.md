---
slug: bug-a-the-selfhost-rule-is-a-no-op-when-the-seed-is-newer-than-its-sources
track: A
type: bug
prio: 45
status: done
blocked-by: []
summary: "`make compiler/pascal26` is described as the one unskippable gate because it IS the byte-identical self-host fixedpoint. In a tree whose seed arrived from outside (a copied-in pinned binary), the seed is newer than the sources, make declares the target up to date, and the rule exits 0 having proved nothing. Caught 2026-08-26 when a full-tier sweep was about to report a verdict for a sha against a binary built from a pin 133 commits older."
owner: opus5-frank1
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

## Outcome

Fixed with option 2 — *"a stamp file as the real target"* — which the ticket
calls the one that makes the property true rather than usually-true. Option 3
("refuse silence") falls out of it for free, and it took a second cut to
actually get.

### The change

`compiler/.pascal26.fixedpoint` records the converged binary's sha256 and round
count, and **the fixedpoint loop is that stamp's recipe, not the binary's**:

```make
$(COMPILER_STAMP): $(COMPILER_SRC) $(COMPILER_INC)
	... the loop, unchanged ... then: printf 'rounds %s\nsha256 %s\n' > $(COMPILER_STAMP)

.PHONY: selfhost-verify
selfhost-verify: $(COMPILER_STAMP)

$(COMPILER): $(COMPILER_SRC) $(COMPILER_INC) $(COMPILER_STAMP) selfhost-verify
	... sha256sum the binary, compare against the stamp, print the provenance ...
```

A binary copied in from outside cannot forge the stamp, so the property stops
depending on where the binary came from. Gitignored beside `compiler/pascal26`
and removed by `distclean`.

### The first cut was wrong, and measuring is how I know

I had `$(COMPILER)` depend on the stamp alone, reasoning that a stamp written
LAST is always newer than the binary, so the verify recipe always runs. Then I
tested it:

```
$ cp stable_linux_amd64/default/pinned compiler/pascal26
$ make compiler/pascal26
make: 'compiler/pascal26' is up to date.
```

The `cp` made the binary newer than the stamp, so the verify was skipped — the
same silence, one level up. **Mtime is not provenance**, which is the whole bug,
and I had reintroduced it in the fix. Only a PHONY prerequisite makes the check
independent of every timestamp. It costs one `sha256sum`, and every target that
depends on `$(COMPILER)` is itself PHONY (they are all `test-*`, `benchmark-*`,
`all`), so nothing cascades.

### Measured

| scenario | before | after |
| --- | --- | --- |
| **the reported bug** — binary newer than every source, no stamp | `make: 'compiler/pascal26' is up to date.`, exit 0, nothing proved | `converged after 1 round(s)` / `self-host fixedpoint: verified — 1 round(s), 4164c65f338c` |
| binary replaced behind the stamp's back | `is up to date`, exit 0 | names both shas, says what happened and how to recover, **exit 1** |
| the recovery it names (delete the stamp, re-run) | — | `converged after 2 round(s)` from the pinned seed |
| nothing changed | `is up to date` | `self-host fixedpoint: verified — 1 round(s), 4164c65f338c` |
| a source changed | rebuilds | rebuilds |

The fourth row is option 3: a gate whose pass and whose skip print the same
thing is not a gate. They now print different things.

### Gate

`tools/selfhost_stamp_devtest.sh`, 7 checks. It uses `make -n`, so it **runs
nothing** — it asks make which recipe it would choose, which is exactly the
question the bug got wrong. Under a second, never builds, never mutates a
binary, never races the watcher; the one file it touches is the stamp, moved
aside and restored.

Wiring it needed a rule: `tools-devtest` globs `tools/*devtest*.py` only, so a
guard written in shell was wired into **nothing at all** — the same condition
`chore-t-five-tool-devtests-are-broken-on-master-and-nothing-runs-them` records
for the Python ones, one file extension to the left. Added `tools-devtest-sh`
beside it (same tally-don't-stop-at-first-red behaviour, in the same
limited/full tiers), which also picks up `tools/devtest_selfhost_race.sh` —
green, and until now run by nothing.

The five TLS/C-interop shell devtests are excluded by name: they have rules of
their own and are deliberately outside the default gate, each needing a network
peer or a system library.

`tools/gate.sh quick` GREEN. Note `gate.sh`'s own self-host step runs
`tools/selfhost_fixedpoint.sh`, which is independent of this rule and unaffected.

### Not done

The stamp records a sha, not a tree state, so it answers *"is this binary a
fixedpoint of the sources as they are now?"* — which is the question make is
asking. It does not answer *"…of sha X"*; a consumer wanting that still has to
pair it with `git status`. The ticket's aside that every sweep, pin and
benchmark needs a machine-readable provenance answer is now half-served and
worth its own ticket if someone wants the other half.

## Log
- 2026-08-26 — resolved, commit 33aa06327.
