# Handover 2026-07-18 — squeeze more float + int performance (Track O)

Fresh-context prompt for the next optimization session. Read this + the two design
tickets, then execute.

## Where we are

- **Float step A done + a residency slice.** `-O3` in-tree XMM fusion
  (c14f35a1) + float loop-residency widened 2→6 xmm regs (813e20eb):
  **mandelbrot 1.31s (-O2) → 0.63–0.67s (-O3)**, checksum byte-identical; FPC
  0.32s → **~2.0–2.1x gap** (was 4.2x).
- **Micro-opts are a proven dead end.** compare-fusion, dead-store-elim,
  float-const-pool ALL measured perf-neutral (see
  [[project_float_intree_xmm_fusion]] / rejected/feature-opt-float-const-pool).
  **Do not re-chase per-leaf float peepholes.** The residual gap is STRUCTURAL:
  frame/stack traffic (~37% of emitted insns on a self-compile: 22.6% push/pop,
  9.4% rbp-loads, 5% rbp-stores) — i.e. register allocation.

## The lever: unified int+float residency via a pxx-owned ABI

Full design (from a long design discussion, all decisions captured):
**`devdocs/progress/backlog/feature-opt-pxx-internal-abi-unified-residency.md`**
(prio 58). The short version:

1. **pxx internal ABI** — pxx→pxx calls owe SysV nothing (freestanding, syscalls
   only unless an extern is explicitly imported). So make `xmm8–15` + `r12–r15`
   **callee-saved in the pxx convention**, **save-iff-used** in prologue (reuse
   the existing `r12–r15` CalleeScratch/residency machinery). This removes the
   "call-free body only" gate on float residency.
2. **Unified residency pass** — one hotness-ranked pass assigns int AND float
   loop locals to free regs of their class (GPR `rbx,r12–r15`; XMM `xmm8–15`),
   generalizing today's separate `LoopResidencyAssign` + `FloatResidencyAssign`.
3. **Barriers** — internal call = FREE (residents callee-saved); extern-C /
   indirect-C call = spill only the LIVE residents (iterate `RcResidentReg` /
   `FrResidentSym`); syscall = XMM-safe; exported pxx fn = present SysV face.

Ratify the register split first (a `decide-*` ABI note, or just write it into
`optimization-architecture.md`) so every backend + hand-asm honors it.

**RECOMMENDED FIRST SLICE (step 1):** on x86-64, make `xmm8–15` callee-saved
save-iff-used + widen the float residency pool + spill-live only at extern/indirect
calls → float residency now works in bodies WITH internal calls. Then measure a
"helper-called-per-iteration" float bench. Low-risk, validates the whole idea.

## Key facts (so you don't re-derive them)

- XMM = 128b/16B, but pxx uses SCALAR double/single → **8-byte `movsd` save** is
  exact and alignment-free (only a future packed-Complex resident needs 16B
  `movaps`, aligned). No `push/pop` for XMM — use a frame slot.
- `Extended` = 80-bit **x87** (separate file, `fldt/fstpt`), NOT in the XMM pool;
  residency is `tyDouble`-only already. Leave x87 out of scope.
- Across a Linux **syscall**, all XMM are preserved (kernel avoids FPU). The
  "caller-saved XMM" hazard is USERSPACE function calls (SysV), not the kernel.
- **aarch64 is easier**: AAPCS64 already makes `V8–V15` (low 64) callee-saved, so
  float residency across calls is FREE there (no custom ABI). 64-bit float
  codegen shares most logic; only encoding differs. `FloatResidencyAssign` is
  x86-64-only today — mirror to aarch64. Per the O charter, perf effort =
  **x86-64 + aarch64 only** (skip 32-bit / xtensa).
- CPU baseline **v2** (SSE3+, universal); v1 ignored; `--arch v3` opt-in; **no
  auto-vectorizer, no runtime multiversioning** — hand-roll hot kernels.

## Adjacent tickets (same lever)
- `feature-opt-complex-packed-double` (prio 35) — Complex as one packed-double XMM;
  `addsubpd` recipe. A complex resident is the 16-byte-save case.
- `feature-opt-store-reload-elimination` (blocked) — unblocks once a liveness
  scaffold exists (the full-allocator someday version).
- `feature-inline-routines` — orthogonal speed lever.

## Gates & discipline (non-negotiable)
- **-O0/-O2 emission unchanged** → self-host byte-identical (`make compiler/pascal26`
  = compile-twice + cmp). Land behind **-O3**; promote per-pass to -O2 only after
  the full matrix.
- **Byte-identical bench checksums** — mandelbrot 74607393270, nbody energy
  258916018. A changed checksum = a correctness regression, NOT a speedup.
- **Smoke EVERY frontend** for any shared change (self-host is necessary NOT
  sufficient): `.pas`/self-host, C-conformance 220/220, `make test-nilpy`, a `.bas`.
  (A prior AST change shipped byte-identical self-host but broke BASIC/C/NilPy.)
- Confirm native (`testmgr --tier quick` + self-host), offload the matrix to
  Track T, push often, land green.
- Forward-declare any helper used above its def in `compiler/forwards.inc` (PXX
  prescan hides the gap; `make bootstrap` under FPC catches it).

## Also this session (context)
14 correctness fixes shipped (float ×2 + C multi-dim/pointer/fnptr arc + 3
csmith-found silent miscompiles + the nested-subscript parser clobber). csmith
loop is clean at reducible complexity; deeper findings can be auto-reduced with
`creduce`/`cvise` (now installed on the box). Method + tools now in
`devdocs/dev/debugging-tips.md`.
