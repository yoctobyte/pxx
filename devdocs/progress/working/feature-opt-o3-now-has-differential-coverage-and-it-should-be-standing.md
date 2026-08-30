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

## 2026-08-30 (frank-optimize) — the cross batch was never run at `-O3`, and the new one is NOT vacuous

### The gap this ticket's item 3 names is wider than it says

`--opts` defaults to `0,2` (`tools/csmith_fuzz.py:595`). The aarch64 batch cited
in the csmith ticket's section D1 — `--target aarch64 --iters 150 --seed-start
300100` — **passes no `--opts`**, so *"136 ran clean across pxx `-O` levels"*
means `-O0` against `-O2`. **aarch64 has never had `-O3` differential coverage
at all**, while carrying 10 `-O3` gate sites by
`tools/check_o3_backend_parity.py`'s count. Filed as
[[bug-t-csmith-batch-records-do-not-state-which-o-levels-they-compared]],
because the wording will mislead the next reader whatever this run returns.

Running now: `--target aarch64 --opts 0,2,3 --iters 150 --seed-start 330000`,
compiler **`ba3d1a18edf6`** (rebuilt first — the binary on disk was three
compiler commits stale).

### First: is a green here worth anything? Rule 2 of the campaign, applied

A batch that never fires the passes is a vacuous green. Measured before
reporting the batch, so the answer does not depend on how it ends.

**Tier level:** aarch64 `-O2` and `-O3` binaries differ on all three probe
seeds, so `-O3` code paths are reached.

**Pass level**, counting the exact word the operand-staging fold skips
(`ldr x0,[sp],#16` = `$F84107E0`) in `.text`, decoded directly — aarch64 is
fixed-width, and local `objdump` has no aarch64 support even though the ELF has
9 section headers and an `AX` `.text`:

| seed | `-O` | instrs | staging pops | density | `ret` |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 330500 | 2 | 196550 | 7850 | 3.99% | 1677 |
| 330500 | 3 | 196550 | 1663 | **0.85%** | 1677 |
| 330501 | 2 | 196550 | 7856 | 4.00% | 1677 |
| 330501 | 3 | 196550 | 1664 | **0.85%** | 1677 |
| 330502 | 2 | 442310 | 20970 | 4.74% | 1701 |
| 330502 | 3 | 393158 | 5512 | **1.40%** | 1701 |

**Identical instruction and `ret` counts at both levels on the small seeds** —
so nothing is inlined away, function count is unchanged, and the 79% drop in
staging is the operand folds alone with the confound held fixed by the data
rather than by an argument.

**But those two rows do not say what they appear to.** Both small programs give
*exactly* 196550 instructions, because `.text` is dominated by the statically
linked RTL — so they measure the fold firing on **the RTL**, not on csmith's
generated code. Subtracting that common baseline from seed 330502 (1096 lines,
the only probe with a large program-specific part):

| | instrs | staging pops | density |
| --- | ---: | ---: | ---: |
| csmith code, `-O2` | 245760 | 13120 | 5.34% |
| csmith code, `-O3` | 196608 | 3849 | **1.96%** |

**71% of the staging in csmith's own code is eliminated at `-O3`.** So the batch
is non-vacuous at pass level too, and a clean result will be worth reporting.

**Two labels I got wrong and am recording rather than quietly fixing.** I first
called `mov x1, x0` (`$AA0003E1`) a control because both arms of the compare
fold emit it — it fell 74%, as fast as the thing it was controlling for, because
other `-O3` arms avoid the staging entirely. And neither stack word is exclusive
to operand staging; prologues use the same encodings. The numbers are a density
argument, not a firing count.

**Residual, and I own it:** this shows the *operand-staging family* fires. It
does not attribute firings to individual slices, and does not show that all 10
aarch64 gate sites are reached. A clean batch clears the family, not each site.

### Firing counts, and three numbers that were not measurements

The section above closes the *family* question by density. The per-slice
question has a real instrument — `PXXDBG` probes, one of which
(`ir_codegen_aarch64.inc:1256`) exists for exactly this reason and says so:
*"There is no aarch64 disassembler on a typical dev box, and a pass that
silently stops firing is invisible to every correctness check we own."*

On csmith seed 330502, `--target=aarch64 -O3`:

| probe | count | what it is |
| --- | ---: | --- |
| `a.w2` | **105** | a real firing count — the aarch64 in-place-ALU slice |
| `a.resid` | **2280** | real — residency decisions, both backends probed |
| `a.forinit` | **2** | real — `ir.inc`, shared |
| `a.a64binop` | 18778 | **a POPULATION, not firings.** The comment says `REPORT ONLY` |
| `a.w1left` | 0 | **meaningless here** — its only live site is in `ir_codegen.inc`, x86-64 |
| `a.w1cmp32` | 0 | same |
| `a.reload` | 0 | **no live probe exists** — two text mentions, zero `PxxDbgEnabled` sites |

**Four of those seven rows are not what they look like, in four different
ways**, and every one of them answers rather than erroring: a population read as
a result, two probes belonging to the other backend, and one probe that no
longer exists. The check that separates them is one grep —
`grep -rc "PxxDbgEnabled('<tag>')" compiler/` — and which FILE the site is in.

**So the honest residual is narrower and sharper than I banked above.** csmith
code at `-O3` on aarch64 provably fires W2 (105) and exercises residency (2280).
**The aarch64 compare fold and the widen fusion — the two slices this session
landed — have no probe at all**, so whether csmith reaches them is not merely
unmeasured, it is unmeasurable with the instruments in the tree. Adding a probe
to each is the obvious next step and it is cheap; I am naming it rather than
doing it under this ticket, since it is campaign work, not coverage work.

### Provenance of the binary under test

`ba3d1a18edf6` is a **binary sha256**, not a commit. The commits in it that
matter, all verified ancestors of HEAD:

- `ba99a4e81` — generic method body / `try`+`asm` `end`-counting fix
- **`f370bb085` — the shared-IR control-flow rewrite the pin is held on**
  (`IRMarkReachableLabels`, `IROptDeadCode`'s own fixpoint deleted, strictly
  more deletion than before)
- `931b43ae0` — `MAX_GENERIC_METHODS` 512 → 2048

That makes this batch incidental evidence about `f370bb085`: a control-flow-heavy
generator against a brand-new dead-code eliminator. **It is not a substitute for
the queued full tier** — different question, different matrix — but it was not
commissioned for it, which is worth stating plainly rather than letting it be
read as coverage it is not.
