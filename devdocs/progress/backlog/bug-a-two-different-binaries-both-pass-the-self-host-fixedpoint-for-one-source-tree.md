---
track: A
prio: 55
type: bug
status: open
found: 2026-08-31
found-by: frankA
owner: ""
blocked-by: []
summary: "`make compiler/pascal26` converged to TWO different binaries from one unmodified source tree on the same machine within an hour: abea85c67b094be9 and b11f52fb431669ab, differing in SIZE (10292256 vs 10292312 bytes) and in 7.8M bytes throughout -- not an embedded timestamp, a different amount of emitted code. BOTH print `self-host fixedpoint: verified`, both compile the test suite correctly, and the SAME seed binary produced each of them at different times with `git diff HEAD -- compiler/ lib/` empty both times. So the fixedpoint check proves SELF-REPRODUCTION, which is all CLAUDE.md claims for it, but the compiler sha is NOT a function of the source tree -- and agents are told to report that sha as provenance beside every measurement. ROOT CAUSE NOT ISOLATED. Named lead, checked and real: compiler/builtin/builtinheap.pas and stable_linux_amd64/default/builtin/builtinheap.pas DIFFER right now, so 'the builtin sources' is a build input living in two places that disagree, and which one a given round reads depends on which binary seeds it."
---

# Two different binaries both pass the self-host fixedpoint for one source tree

Found incidentally while using the compiler sha as provenance for a bug fix, per
the workflow rule to *"print `sha256sum compiler/pascal26` beside every number
you report"*. The sha moved under a source tree that never changed.

## Measured

`git diff HEAD -- compiler/ lib/` empty for every row. Same box, same hour.

| when | seed | rounds | result |
| --- | --- | --- | --- |
| T1 | `pinned` | 2 | `abea85c67b094be9` |
| T1 | `abea85c67b09` (itself) | 1 | `abea85c67b094be9` |
| T2 | `pinned` | 2 | `b11f52fb431669ab` |
| T2 | `abea85c67b09` | 1 | `b11f52fb431669ab` |
| T2 | `abea85c67b09` | 1 | `b11f52fb431669ab` (repeat) |

**The fourth row is the load-bearing one:** the *same seed*, on the *same
sources*, produced itself at T1 and something else at T2 — so this is not
"two basins, one per seed". Within a moment it is perfectly reproducible; across
that hour it is not.

```
size:            10292256   vs   10292312     (+56 bytes)
differing bytes: 7823144                      (of ~10.3M)
first diffs at:  offsets 153, 161, 238, 334, 339
```

A wholesale layout difference and a different code size — **not** a baked-in
timestamp or path, which is what a small localised diff would have meant.

Both binaries are CORRECT: each compiles and passes
`test_pointer_to_dynamic_array_indexing` (30/30), the parallel SetLen test, and
the FPC differential.

## Why it matters

- **A compiler sha is not a source identity.** Two agents on the same commit can
  legitimately hold different binaries. Every provenance line of the form
  "measured at sha X" is weaker than it reads — it identifies the binary, which
  was the point, but it cannot be reproduced from the commit.
- **`make pin` blesses whichever of these happens to be on disk.**
- The `self-host fixedpoint: verified` line remains **true and worth having** —
  CLAUDE.md only ever claims *"our binary reproduces itself"*, and both do. This
  ticket does not weaken that claim; it bounds it. Self-reproduction is not
  canonicity, and the gate was never sold as canonicity.

## The lead, checked but NOT proven to be the cause

`compiler/builtin/builtinheap.pas` and
`stable_linux_amd64/default/builtin/builtinheap.pas` **differ today** (the local
one was changed this session and the pin has not moved since). The builtin units
are compiled into every program, so they are a build INPUT — and they exist in
two trees that are allowed to disagree. Which copy a round reads plausibly
depends on which binary is seeding it, which would explain a convergence that
depends on build history rather than on sources.

**Do not record this as the answer.** What is established is the divergence and
that it is a real input; the connection to the two shas is a hypothesis. The
experiment that would settle it: make the two builtin trees identical, then
repeat the T1/T2 table and see whether the split survives.

Second candidate, cheaper to rule out: `compiler/.pascal26.fixedpoint` and the
`pascal26_p2.map` / `pascal26_probe.map` artefacts are untracked build state
that survives across builds; check whether removing them collapses the split.
