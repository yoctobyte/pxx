---
prio: 35  # Track O — float codegen; the remaining mandelbrot gap after xmm-fusion
type: feature
---

# -O3: load float constants from a data pool, not GPR materialization

- **Type:** feature (optimization — Track O; Track A files/gate). x86-64 (aarch64
  mirror later).
- **Opened:** 2026-07-18, after [[feature-opt-float-intree-xmm-fusion]] +
  the residency expansion closed the transfer/reload gap.

## The remaining gap

After xmm-fusion + residency, `bench/portable/mandelbrot.pas` is -O3 **0.63s** vs
FPC **0.32s** (was 1.31s at -O2; 4.2x → 2.0x). A chunk of what's left is **float
constant materialization**: the value model carries a Double as its bits in rax,
so a float literal in a hot loop (`2.0*zre*zim`, the `4.0` escape test) emits
`movabs rax, <bits>` + `movq xmm, rax` **every iteration**. FPC keeps the constant
in memory and folds it into the op: `mulsd xmm, [rip+const]`.

In `EmitFloatTree` a float-const leaf (`IR_CONST_INT` with a float `IRTk` = double
bits) currently goes through `IREmitNode` (movabs) then `movq xmm,rax`. Replace
with a single `movsd xmm<dst>, [pool]` from a deduped read-only double pool.

## Why it is not a trivial slice

The BSS-global float load already uses `movsd xmm,[abs32]` via `EmitGlobRef`
(4-byte disp32 fixup). But a *constant* needs INITIALIZED data:
- `EmitDataRef` emits a **pointer-width (8-byte)** absolute address — wrong width
  for the `movsd [04 25 disp32]` operand (needs 4 bytes).
- So this needs one of: a new **4-byte data-address fixup**, or emit the 8 bytes
  to BSS + a startup initializer (like globals), or **RIP-relative** addressing
  (`F2 0F 10 /r` with a mod=00 rip disp32 + a pc-relative fixup). RIP-relative is
  the cleanest and smallest code, but is new fixup machinery.

## Scope

- A per-compile deduped pool of 8-byte doubles (map bits -> data offset).
- `EmitFloatTree` float-const leaf -> `movsd xmm<dst>, [pool]`.
- Ideally also fold a const operand straight into the arith op
  (`mulsd xmm,[pool]`) — bigger, do the load form first.
- **-O3 only** (EmitFloatTree is -O3), so -O0/-O2 stay byte-identical for
  self-host. Numerically identical (same 8 bytes) — mandelbrot checksum MUST stay
  74607393270.

## Acceptance

- mandelbrot/nbody faster at -O3, checksum/energy byte-identical.
- No integer/-O2 regression; C float differential (O0/O2/O3) stays clean.
- Gate: `make test` + self-host byte-identical + the bench suite.

## REJECTED 2026-07-18 — implemented, correct, but PERF-NEUTRAL

Implemented end to end (added a 4-byte DATA-abs fixup list `DataFix32` mirroring
GlobFix; EmitDataRef32; writeELF apply-loop; EmitFloatTree float-const leaf ->
8-byte pool + `movsd xmm,[abs32]`). Result: mandelbrot -O3 **0.64s vs 0.63s**
(neutral/noise), nbody unchanged — checksum/energy byte-identical, self-host
byte-identical. The `movsd` from an L1-hot pool is not cheaper than `movabs rax +
movq`; the constant materialization was never the bottleneck. REVERTED.

Broader finding: THREE float micro-opts now measure perf-neutral on mandelbrot —
compare-fusion, dead-store-elim, and const-pool (see
[[project_float_intree_xmm_fusion]]). The residual gap vs FPC (0.63 vs 0.32) is
therefore STRUCTURAL — instruction scheduling / the arithmetic dependency chain /
FPC's cross-loop register allocation — not the remaining GPR<->XMM transfers or
constant loads. Further float wins need a real scheduler or a genuine xmm-resident
value model across the whole loop, not more per-leaf peepholes. Don't re-attempt
const-pooling without a const-materialization-bound benchmark proving a win.
