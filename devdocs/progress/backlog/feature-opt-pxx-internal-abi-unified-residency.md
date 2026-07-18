---
prio: 58  # Track O — the register-allocation lever, right-sized via the pxx-owned ABI
type: feature
---

# pxx internal calling convention + unified int/float residency allocator

- **Type:** feature (optimization — **Track O**; file-ownership **Track A**: edits
  the shared prologue/epilogue, `symtab.inc` residency, backends). Under the
  [[feature-opt-o3-register-pressure]] umbrella; supersedes the "big register
  allocator" framing with a smaller, ABI-driven design.
- **Opened:** 2026-07-18 (design discussion). x86-64 first, aarch64 mirrors.

## The key realization

pxx is freestanding — **pxx→pxx calls do not owe SysV anything.** SysV only
governs the boundary with explicitly-imported externs (opt-in, detectable at the
call site). So pxx can define its OWN internal convention and make the residency
registers **callee-saved**, which removes the "call-free body only" gate that
limits float residency today and lets int+float unify under one rule.

Measured motivation (unchanged): ~37% of emitted instructions on a self-compile
are frame/stack traffic (22.6% push/pop, 9.4% rbp-loads, 5% rbp-stores), not
compute. r14/r15 param residency alone already bought ~1.34x from 2 registers.

## Design (three pieces, each reuses existing machinery)

### 1. pxx internal ABI: widen the callee-saved set
- Declare `r12–r15` (already) **and `xmm8–15`** callee-saved in the pxx internal
  convention, **save-iff-used** in prologue/epilogue (the Windows insight: the
  callee knows its own needs, so each register is saved by exactly one function,
  not defensively by every caller). Reuse the existing `r12–r15`
  CalleeScratch/residency save path for the xmm set.
- XMM save cost is **8 bytes** per resident, not 16: pxx uses XMM only for SCALAR
  `Double`/`Single` (low 64/32 bits) — `movsd [slot], xmm` (no alignment req).
  `Extended` is x87 (80-bit, separate file), NOT in this pool. There is no
  `push/pop` for XMM; use a reserved frame slot.

### 2. Unified residency pass
- One pass ranks the hottest loop-range locals/params (int AND float) by access
  count and assigns each to a free register **of its class** (GPR pool
  `rbx,r12–r15`; XMM pool `xmm8–15`). Generalizes `LoopResidencyAssign` +
  `FloatResidencyAssign` (today separate, structurally identical) into one.
- Widen the pools: int today uses ~4, float now 6 (`xmm8–13`) — go to the full
  callee-saved sets.

### 3. Call barriers (the only spill sites left)
- **Internal pxx call:** FREE — residents are callee-saved, survive it.
- **Extern C call / indirect call in C mode:** SysV clobbers XMM (and caller-saved
  GPRs), and an indirect target can't be proven to honor the pxx ABI → spill only
  the **live** residents around the call (iterate the active assignments —
  `RcResidentReg`/`FrResidentSym` — save just those, restore after; save-only-live,
  not save-all).
- **syscall:** XMM-safe (Linux preserves XMM across syscalls) — no spill.
- **Exported/`public` pxx function (called FROM external C):** must present the
  SysV face at that boundary — save per SysV in its prologue (detectable: symbol
  is exported).

## Why this is smaller than "a register allocator"

Residency (hotness-ranked, loop-scoped) + save-iff-used + spill-live-at-extern
sidesteps the interference graph entirely for the hot 80%. A full linear-scan /
graph-coloring allocator (with a liveness scaffold, which also unblocks
[[feature-opt-store-reload-elimination]]) stays the *someday* version; do the
ABI+residency first and measure how much gap remains.

Bonus door pxx uniquely can open later: because it compiles the WHOLE internal
program, the save-set / assignment can go INTERPROCEDURAL (a callee informed by
its callers) — impossible for SysV/Windows compiling TUs separately. Not v1.

## aarch64: mostly FREE — no custom ABI needed

64-bit float codegen SHARES most of this logic across x86-64 and aarch64 (ARM's
V0–V31 are the XMM equivalent; scalar `Dn`/`Sn` = XMM low-lane). Differences are
minor (encoding; FMA is baseline on ARM; no 80-bit/x87 — `Extended` = double).
Push the shared parts down into the IR/residency layer, keep only encoding
per-backend.

Crucially, **AAPCS64 already makes `V8–V15` (low 64 bits) callee-saved.** So on
aarch64, float residency survives calls under the STANDARD ABI — the custom
callee-saved convention in piece #1 is an **x86-64-only** fix (SysV made all XMM
volatile). On ARM just use V8–V15 as the ABI intends. Plus 32 V + 31 X registers
= far lower register pressure / more residents. Complex: ARMv8.3 `FCMLA`/`FCADD`
(optional) or base NEON. `FloatResidencyAssign` is x86-64-only today; the aarch64
mirror is simpler than x86 precisely because the ABI hands over callee-saved
float for free.

## CPU-feature baseline (x86-64)

Ratified in discussion: **v2 minimal** (SSE3/SSSE3/SSE4 — universal ~15 yrs;
gives `addsubpd`/`movddup` for complex). **v1 ignored** (early buggy 64-bitters).
`--arch v3` (AVX2/FMA) as an opt-in for known targets. **No runtime
multiversioning, no auto-vectorizer** — hand-roll the few hot kernels (mandelbrot/
raytracer) in asm instead. See [[feature-opt-arch-level-and-dispatch]] if raised.

## Prereq: ratify the ABI

Defining a non-SysV pxx internal convention is an ABI decision — write it in
`devdocs/dev/optimization-architecture.md` (or a short ABI doc) and get the
register split signed off (see the sibling `decide-pxx-internal-abi-register-split`
if raised) BEFORE code, so every backend + any hand-asm honors it.

## Acceptance

- Float residency works in bodies WITH internal calls (not just call-free);
  int+float share one residency pass over the widened pools.
- mandelbrot / nbody faster at -O3, checksums byte-identical; a call-in-loop float
  bench (helper called per iteration) shows the win. No integer/-O2 regression.
- Gate: `make test` + self-host byte-identical (-O0/-O2 unchanged; land behind -O3,
  promote per-pass after the full matrix) + cross where a backend is touched.
