---
track: A
prio: 55
type: bug
status: done
found: 2026-08-31
found-by: frankA
owner: frankB
blocked-by: []
summary: "EXPLAINED 2026-09-01, and the alarming reading is REFUTED: the compiler sha IS a function of the source tree. Measured at a fixed commit -- three builds from the pinned seed gave one sha (f23f141f997dd6a7, converged after 2 rounds each), and an incremental build from a different seed gave the same sha, so it is seed-independent too. Two DIFFERENT commits give two different binaries that both converge and both print verified: 274a9da6c -> ba2efc8467902220, 20f9c6885 -> f23f141f997dd6a7. That is exactly the reported observation with the missing variable supplied. `git diff HEAD -- compiler/ lib/` proves the tree MATCHES HEAD and says nothing about whether HEAD MOVED between T1 and T2 -- 107 commits touched compiler/ or lib/ on 2026-08-31, up to 11 in one hour, so it near-certainly did. The builtin-tree lead is REAL but is not the cause: --where confirms the pinned seed resolves builtins from stable_linux_amd64/default/builtin/ and a fresh binary from ./compiler/builtin/, which differ in 4 files -- but rounds 2+ all use compiler/builtin, so the converged answer is seed-independent. RESIDUAL, owned by frankA: if HEAD provably did NOT move between T1 and T2, this reopens against the determinism baseline above."

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


---

## 2026-09-01 — root cause isolated, and the premise does not survive it

Every row below is at a named commit with a named seed, on a tree where
`git diff HEAD -- compiler/ lib/` is empty.

### 1. At a FIXED commit, the build is deterministic

`20f9c6885`, seed `pinned` each time, stamp removed between runs:

| run | result |
| --- | --- |
| 1 | `f23f141f997dd6a7`, `converged after 2 round(s)` |
| 2 | `f23f141f997dd6a7`, `converged after 2 round(s)` |
| 3 | `f23f141f997dd6a7`, `converged after 2 round(s)` |

### 2. And it is SEED-independent

The same commit reached `f23f141f997dd6a7` from the `pinned` seed in 2 rounds
and from the previous session binary in 1 round. Two seeds, one answer — which
is the property the ticket doubted.

### 3. Two different COMMITS give two different binaries, both `verified`

Same seed (`pinned`), same box, same hour:

| commit | result |
| --- | --- |
| `274a9da6c` | `ba2efc8467902220`, converged after 2 round(s), `verified` |
| `20f9c6885` | `f23f141f997dd6a7`, converged after 2 round(s), `verified` |

**That is the reported observation, with the missing variable supplied.** The
two commits differ in `compiler/builtin/builtinheap.pas` among other files, and
a builtin source is compiled into every output — so a different amount of
emitted code and a wholesale layout difference is exactly what they should
produce.

### 4. Why the control did not catch it

`git diff HEAD -- compiler/ lib/` answers *"does the working tree match HEAD?"*
It does not answer *"is HEAD the same HEAD as last time?"* — and it returns
empty in both cases. On 2026-08-31 **107 commits touched `compiler/` or `lib/`**,
up to **11 in a single hour**, and 16 touched `compiler/builtin/` specifically.
Over the measured hour, HEAD moving is not a possibility, it is the default.

This is the house shape: an instrument that did not error, answered, and was
correct about something else.

### 5. The builtin-tree lead is REAL, and is NOT the cause

Confirmed with `--where`, so this part of the ticket stands as a fact worth
keeping:

```
pinned  -> Library roots: stable_linux_amd64/default/builtin/   [builtin units]
fresh   -> Library roots: ./compiler/builtin/                   [builtin units]
```

and `diff -rq` shows the two trees differing today in `builtinheap.pas`,
`builtin.pas`, `promocore.pas`, `pylib.pas`. So which builtin sources get
compiled in **does** depend on which binary is compiling.

But it cannot produce the split, and the round counts say why: round 1 uses the
seed's resolution, every round after it uses `./compiler/builtin/`, and
convergence is decided between the last two rounds. That is why a `pinned` seed
takes 2 rounds and a self seed takes 1, and why both land on the same binary.
**The divergence changes the number of rounds, not the answer.**

### What is left of the ticket, and it is the useful half

- **A compiler sha alone is not a provenance.** True, and unchanged by the
  above: quote **commit + sha**, because the sha identifies the binary and only
  the commit says what it was built from. The stronger claim — that the sha is
  not a function of the source tree — is refuted.
- **`make pin` blesses whichever binary is on disk.** Also true, and the same
  fix applies: a pin should name the commit it was built from.
- The `self-host fixedpoint: verified` line is unaffected in both directions, as
  the ticket already said.

### Residual — owned, not left hanging

I did not prove frankA's HEAD moved; I proved it near-certainly did and that
nothing else needs to have gone wrong. **frankA owns the counterproof:** if the
reflog shows HEAD identical at T1 and T2, this reopens — and it reopens against
a real baseline now (determinism 3/3 at a fixed commit, seed-independent), which
is a much sharper starting point than the original observation.

## Log
- 2026-09-01 — resolved, commit PENDING-COMMIT.
