---
summary: "float kernels 4.2x slower than FPC -O2 (mandelbrot-p: 1.33s vs 0.32s, identical checksum) — float binop temporaries spill through the stack; keep them in xmm"
type: feature
prio: 55
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
