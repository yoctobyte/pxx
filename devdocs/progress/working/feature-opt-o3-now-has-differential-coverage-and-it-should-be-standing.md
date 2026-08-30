---
track: A
prio: 40
type: feature
status: working
blocked-by: []
owner: frank-optimize
summary: "-O3 is the free tier for new passes precisely because nothing gates OptLevel>=3. As of 2026-08-30 it has 443 programs of csmith self-differential coverage (pxx -O0 vs -O2 vs -O3, zero MISCOMPILE_OPT) -- an oracle-free check no gcc-disagreement argument can touch. Proposes making it standing per new -O3 pass rather than a one-off."
---

# `-O3` now has differential coverage, and it should be standing

- **Track O** (work-tag) — **file-owned by Track A**, gated by A's rules, per
  CLAUDE.md's rule that an O ticket carries A's file ownership.
- **Found:** 2026-08-30 by frankC, running the csmith campaign. Filed rather than
  written into `devdocs/dev/optimization-architecture.md` because that file is
  A/B ground and Track O agents may be in it; **a line there is still the right
  permanent home** — see "What I am asking for" below.

## What now exists

`tools/csmith_fuzz.py --opts 0,2,3` ran for the first time on 2026-08-30, across
two batches:

| batch | seeds | complexity | agreed | skipped | `MISCOMPILE_OPT` |
| --- | --- | --- | ---: | ---: | ---: |
| A | 1-200 | default | 175 | 25 | **0** |
| B | 40000-40299 | full | 268 | 32 | **0** |

**443 comparisons, zero optimisation-level divergences.** Compiler
`f2bfbb3c94a5`, a self-host fixedpoint at HEAD `f278ddaca`.

Reproduce:

```sh
tools/csmith_fuzz.py --iters 300 --seed-start <unused> --opts 0,2,3
```

## Why this is the strongest kind of check available here, and specific to `-O3`

CLAUDE.md makes `-O3` the landing tier for new passes on an explicit basis:
it is *"a free tier — **nothing gates `OptLevel>=3` yet**"*, with promotion to
`-O2` per-pass only after the full gate. That freedom is the point, and the cost
of it is that a `-O3`-only miscompile has, until now, had **no differential
coverage anywhere in the repo**.

What the harness adds is not another oracle but a **self**-differential: it
builds the same csmith program at `-O0`, `-O2` and `-O3` with the same compiler
and compares the checksums. So:

- **No oracle is involved**, and therefore no "gcc is wrong here" conversation is
  available. A disagreement between our own `-O0` and `-O3` is a miscompile we
  own outright.
- **The programs are UB-free by construction** (csmith's whole premise), so a
  divergence cannot be dismissed as the test's fault either.
- It is **orthogonal to the corpora**. lua/zlib/sqlite are written by humans who
  avoid dark corners; this campaign's own history records nine bugs found in one
  sitting that *none* of those corpora could reach.

It cannot be argued with, only extended. That is a rare property and it is worth
knowing it now applies to the tier where the newest, least-exercised passes live.

## What this does NOT prove

443 dry programs narrow the space; they do not clear it. Both batches were
**x86-64 native** — a `-O3` pass with a backend-specific arm (the aarch64
peephole and register-allocator work, say) is untouched by this. `--target` works
and a cross batch is running as this is filed; until it reports, `-O3`'s
differential coverage is x86-64 only and should be described that way.

Nor does it substitute for the full gate on promotion to `-O2`. It is evidence a
pass does not miscompile the kind of code csmith writes, which is a narrower
claim than correctness.

## What I am asking for

1. **Record that this coverage exists** where pass authors will see it — one line
   in `devdocs/dev/optimization-architecture.md`, which I did not edit because it
   is not Track C's file. Someone holding A/B should add it.
2. **Make it standing rather than a one-off.** A new `-O3` pass is exactly the
   change this check is sensitive to, and it costs one command. Suggested shape:
   a batch of a few hundred at `--opts 0,2,3` in unused seed space when a pass
   lands in the free tier, with the seed range recorded so the next author does
   not re-walk it.
3. **Extend to cross targets** as `--target` batches come in, so a per-backend
   `-O3` arm is covered by the same oracle-free check.

Track T owns the harness; this ticket asks nothing of that file. It asks Track O
to adopt a check that already exists.
