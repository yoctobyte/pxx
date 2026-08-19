---
summary: "float kernels: -O3 now 1.97x vs FPC (was 4.2x); residual = the rax value model — multi-session xmm-resident rewrite"
type: feature
prio: 20  # user 2026-07-19: general code speed over float — parked lower
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

## Re-measured 2026-07-18 night (fable-O) — gap HALVED since opening, arc still valid

Same box, same checksum (74607393270), quiet machine, hyperfine w2/r7:

| build | time | vs FPC -O2 |
| --- | --- | --- |
| pxx -O2 | 1.399 s ± 0.009 | 4.2x (unchanged — ticket baseline) |
| **pxx -O3** | **0.664 s ± 0.005** | **1.97x** |
| FPC -O2 | 0.337 s ± 0.003 | 1.00x |

- The opening's "-O3 is WORSE (2.47s)" is DEAD: -O3 now carries in-tree XMM
  fusion (c14f35a1), 6-slot xmm residency across calls (the internal-ABI arc,
  cc9bfd17..2dffbb7c), unified int+float residency and caller-side regcall —
  mandelbrot 2.47s → 0.66s since the ticket was filed.
- The residual ~2x against FPC is exactly this ticket's diagnosis: the rax
  VALUE MODEL at tree/statement boundaries (movq transits + stack rounds
  where trees meet stores, compares, calls). Fusion killed the WITHIN-tree
  cost; the xmm-resident value model remains the multi-session fix and stays
  the honest scope of this ticket. Do-not-night-tail note still applies.

## Re-confirmed 2026-08-15 from a SECOND workload (Track B, transcendental kernels)

Independent measurement, different code, same root — recorded because it puts a
clean isolated number on the value model and separates it from two things that
were being blamed instead.

`lib/rtl/math.pas`'s new fast `Sin` vs **the identical algorithm compiled by
gcc -O2 -mno-fma** (same instruction set, no FMA, so this is codegen alone), 1M
calls:

| variant | time | what it isolates |
| --- | --- | --- |
| pxx `Sin`, as shipped | 131 ms | |
| pxx, only the needed kernel (skip the wasted cos) | 77 ms | **1.5x** — algorithmic, Track B's to fix |
| pxx, hand-inlined into ONE function, zero calls | 65 ms | **1.2x** — call overhead |
| **gcc, same source, same ISA** | **9 ms** | **7.2x — the value model** |
| glibc `sin` | 7 ms | 1.3x — glibc's extra fast paths |

**Call overhead is 1.2x here, not the story.** That matters because
[[feature-opt-inline-float-and-record-returning-leaves]] was filed the same day
off a 3.8x inlining measurement — but that was on the *double-double* kernels,
which are ten-op functions called 26 times per evaluation. On ordinary
plain-double code the inliner is worth ~20%, and this ticket is worth 7x.

Disassembly of the hand-inlined pxx function (`--map`, then objdump on the raw
image — pxx ELFs carry no section headers):

```
811 instructions total
 80   real float arithmetic
316   movq xmm<->GP moves        <- gcc emits ZERO for the same source
125   stack-slot references      <- gcc: 8
 61   instructions in gcc's whole function
```

10 instructions emitted per one of arithmetic. The signature pattern, verbatim:

```asm
mulsd  xmm0,xmm1
movq   rax,xmm0                    ; result out to the integer file
movq   xmm0,rax                    ; ...and straight back, a pure no-op
movsd  QWORD PTR [rbp-0xb8],xmm0   ; spill
movsd  xmm0,QWORD PTR [rbp-0xb8]   ; reload, next instruction
```

28 of those `movq r,xmm ; movq xmm,r` pairs are *provably* dead in this one
function, and 12 store/reload pairs touch a slot that was live in a register.

Two notes for whoever takes this:

- `Abs()` is still a **call** in the emitted code (2 calls survive the full
  hand-inline). `andpd` with a sign mask is one instruction; worth checking
  whether it is a builtin at all.
- This workload is a better acceptance metric than mandelbrot for the *scalar*
  half: no array indexing, no loop-carried dependence, just a Horner chain —
  so it measures the value model almost neat.

**Still the user's call on priority** (parked at 20 on 2026-07-19, "general code
speed over float"). Recording the number, not arguing the rank: the scope has
widened since — every frontend's float path, `lib/rtl` math, and the ESP/sensor
work all sit on this emission.
