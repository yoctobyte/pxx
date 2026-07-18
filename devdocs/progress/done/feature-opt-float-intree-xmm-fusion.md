---
summary: "Keep float binop-tree intermediates in xmm (no push/pop/GPR-transit) within one expression — most of the 4.2x float gap, small blast radius"
type: feature
prio: 40
---

# Track O: in-tree xmm fusion for float expression temporaries

- **Type:** feature (optimization — Track O; Track A files/gate). Per-backend value-model
  work, NOT a shared-IR pass — **x86-64 first**, aarch64 later, per the O charter
  (32-bit/ESP keep their models).
- **Status:** done
- **Opened:** 2026-07-18, split out of [[feature-opt-float-register-temporaries]] as its
  actionable first slice.

## Why this, split from the big ticket

[[feature-opt-float-register-temporaries]] is the FULL fix: an xmm-resident float value
model touching every float consumer (binops, compares, call args/returns, stores,
writeln) — a multi-session arc. This ticket is the **narrow subset that captures "probably
most of the win" with a one-expression-tree blast radius** and no cross-statement state.
Do this first; the full value-model arc stays the someday version.

## The gap (bench oracle)

`bench/portable/mandelbrot.pas`: pxx -O2 **1.33s** vs FPC -O2 **0.32s** = **4.2x**, with
an IDENTICAL checksum (74607393270 @1600x1200) — same work, worse codegen. Root: the
x86-64 value model carries a Double as **raw bits in RAX**, so each float `IR_BINOP`
emits **3 GPR↔XMM transfers + a stack round-trip**:

```
eval left -> rax, push rax; eval right -> rax, mov rcx <- pop;
movq xmm1, rax; movq xmm0, rcx; <op>; movq rax, xmm0
```

The mandelbrot inner loop (`zr*zr - zi*zi + cr`, …) round-trips every temporary through
memory + GPR.

## Scope of THIS ticket

- Within a single float expression tree, evaluate to **xmm2..xmm5** and keep intermediates
  resident — no `push/pop`, no `movq rax<->xmm` transit between sub-operations of the same
  tree. Spill only when the tree's register budget is exceeded (as MOVSD, not GPR-transit).
- Binop-tree only. Cross-statement float locals staying xmm-resident is the *big* ticket
  (regcall-style residency with the same guards) — explicitly OUT here.
- **-O0 unchanged** — the GPR-transit accumulator stays the simple debuggable baseline;
  this is -O2+/-O3 behavior (Track O promotion: land behind -O3, promote to -O2 after the
  full gate).

## The -O3 entanglement

**-O3 currently makes float WORSE** (2.47s) — the W1 operand scheduler
([[project_o3_w1_operand_scheduler]]) pessimizes float chains. So landing this behind -O3
must NOT compose with W1's float pessimization: either make W1 xmm-aware or gate W1 off
for float trees as part of this work. May be a quick standalone win on its own.

## Acceptance

- `mandelbrot-p` (and `nbody`) measurably faster at the target -O level, with the
  **checksum BYTE-IDENTICAL** (strict IEEE, no FMA contraction — the bench header documents
  why; a differing checksum is a correctness regression, not a speedup).
- No regression on the integer benches or the -O2 default.
- Gate: `make test` + self-host byte-identical (-O0 emission unchanged) + the bench suite.

## Non-goals

- Not the full xmm-resident value model (that's [[feature-opt-float-register-temporaries]]).
- Not aarch64 in v1 (x86-64 first; aarch64 mirrors after).
- Not FMA / reassociation — checksums must stay bit-identical.

## Log
- 2026-07-18 — resolved, commit c14f35a1.
