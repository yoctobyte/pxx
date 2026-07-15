---
summary: "float kernels 4.2x slower than FPC -O2 (mandelbrot-p: 1.33s vs 0.32s, identical checksum) — float binop temporaries spill through the stack; keep them in xmm"
type: feature
prio: 35  # user 2026-07-15: worth a ticket, not high prio
---

# Track O: float expression temporaries in registers

- **Type:** feature (optimization — Track O, i.e. Track A files/gate).
- **Opened:** 2026-07-15 morning, from the portable-bench oracle the T lane
  added the night before (bench/portable/mandelbrot.pas, 421bdfe7): both
  compilers produce the IDENTICAL checksum (74607393270 @1600x1200), so the
  work is the same — pxx -O2 1.33s vs FPC -O2 0.32s = 4.2x. This is exactly
  the "external speed oracle" that bench was built to provide.
- **-O3 is WORSE** (2.47s): the W1 operand scheduler pessimizes the float
  kernel — consistent with the recorded "judge codegen on compute benches"
  note (project_o3_w1_operand_scheduler). Worth a look while in there.

## Where the 4x goes

The x86-64 float binop path is an accumulator machine: each IR_BINOP loads
operands from stack slots, computes in xmm0/xmm1, and spills the result back
(EmitFloatSpill386-style patterns on x86-64 too). The mandelbrot inner loop
(zr*zr - zi*zi + cr etc.) round-trips every temporary through memory; FPC
keeps the whole escape iteration in registers.

## Recon (2026-07-15 morning — root confirmed)

The x86-64 VALUE MODEL carries a Double as raw bits in RAX. A float
IR_BINOP therefore emits: eval left -> rax, push rax; eval right -> rax,
mov rcx<-pop; movq xmm1, rax; movq xmm0, rcx; <op>; movq rax, xmm0. Three
GPR<->XMM transfers plus a stack round-trip PER OPERATION — the whole 4.2x
against FPC's xmm-resident code. The narrow "fuse within one tree" idea
still pays, but the honest fix is an xmm-resident float accumulator
(xmm0 = the float accumulator; nested left operands spill to the stack as
today, but as MOVSD spills, no GPR transit), which touches every float
consumer: binops, compares, call args/returns, stores, writeln. Sized as
a MULTI-SESSION Track O arc — do not start it as a night-tail.

## User constraints (2026-07-15)

- **Not high prio** — worth the ticket, not a campaign.
- **-O0 keeps today's emission exactly** (the GPR-transit accumulator stays
  the simple, debuggable baseline); the xmm-resident evaluation is an
  optimization LEVEL behavior (-O2+, or -O3 first per the Track O promotion
  rule).
- **Highly platform-specific**: this is per-backend value-model work, NOT a
  shared-IR pass — x86-64 (and aarch64 later) only, per the O charter;
  32-bit/ESP targets keep their existing models. (Note: FPC's exact codegen
  strategy for its 4x — FP stack vs SSE — is its business; our number comes
  from the bench oracle either way.)

## Shape (per the regcall/residency precedents)

- xmm residency for float LOCALS mirrors the -O2 regcall integer residency
  (project_regcall_phase0_1_v172): the same guards (no inline asm, no
  generators, refresh at handler entry per the longjmp landmine).
- Or narrower: fuse the binop chain within one expression tree (keep
  intermediates in xmm2..xmm5 instead of push/pop) — no cross-statement
  state, much smaller blast radius, probably most of the win.
- Gate: -O2 promotion rules per Track O (land behind -O3? -O3 currently
  REGRESSES floats, so fixing/replacing W1 for float chains may be the same
  ticket). x86-64 + aarch64 only per the O charter.
- The bench suite (mandelbrot-p, nbody) IS the acceptance metric; checksums
  must stay identical (strict IEEE, no FMA contraction — the bench header
  documents why).
