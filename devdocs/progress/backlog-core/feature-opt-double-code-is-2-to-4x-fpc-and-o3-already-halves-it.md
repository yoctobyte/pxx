---
track: A
prio: 45
type: feature
blocked-by: []
summary: "Double loops at the default -O2 run 2-4x slower than fpc -O2 because a double lives in its frame slot and travels as raw bits through rax plus a push/pop per operand. The -O3 float residency and in-tree XMM fusion already remove that and halve the gap. What -O3 still loses to fpc is copy chains on the loop-carried path: EmitFloatTree loads each resident leaf into xmm0 and then moves it to xmm<dst>, and each store goes xmm2 -> rax -> xmm0 -> resident. Measured by hand-editing the -O3 loop: removing the copies brings mandelbrot to fpc parity. Two moves: (1) promote the -O3 float residency and fusion to -O2 through the O-lane gate; (2) load and store residents directly."
status: new
owner: ""
---

# Double code is 2-4x fpc -O2, and -O3 already halves it

- **Type:** feature. **Track A**, tagged **O**. `compiler/ir_codegen.inc`
  (`EmitFloatTree` leaf arm; the float store path).
- **Source:** frankd-a3's benchmark, `pxx-website-patches/benchmark-pxx-vs-fpc-2026-09-25.md`:
  mandelbrot 4.06x, nbody 2.20x.
- **Measured 2026-09-25 by frankS.** HEAD `3d8bb6061784` on plexus, Xeon
  E5-2620 v2, with the host shared (load average 4 to 14). Timings are the
  min of 5 or 11 interleaved runs. HEAD's default build of
  `bench/portable/mandelbrot.pas` has sha256 `ba877a8a58af`, the same binary
  the benchmark timed.

## Whole program, same checksum in every row

| program | fpc -O2 | pxx -O2 (default) | pxx -O3 |
| --- | ---: | ---: | ---: |
| mandelbrot (1600x1200) | 583 ms | 2335 ms, **4.01x** | 1216 ms, **2.09x** |
| nbody | 155 ms | 347 ms, **2.24x** | 251 ms, **1.62x** |

## Why -O2 is slow (from the disassembly of the -O2 kernel)

`EscapeCountLimit` is 753 bytes at -O2, against about 100 for fpc. Its loop
is about 100 instructions against fpc's 24:
- every double local stays in its frame slot;
- every operand goes `movsd slot->xmm0; movq xmm0->rax; push rax; ...; pop; movq rax->xmm1`;
- the `while (a) and (b)` condition goes through setcc, movzb and a memory
  byte before the branch.

At -O3, `FrResidentCount` (xmm8-13) and the in-tree fusion
(`feature-opt-float-intree-xmm-fusion`) remove all of this.

## What -O3 still loses: priced by hand-edited asm

The -O3 loop was transliterated into a standalone function. A C harness runs
the benchmark's grid through each variant. It is calibrated against the whole
program: the harness gives fpc 577 ms and pxx-O3 1219 ms, against 583 and
1216 for the real binaries. Every variant printed checksum 74607393270.

| variant of the -O3 loop | x fpc (two runs) |
| --- | --- |
| A: as emitted | 2.22, 2.09 |
| B: A without the movq xmm->rax->xmm bridge at each assignment | 2.09, 1.86 |
| E: A without the movaps copy chains only | **1.53, 1.41** |
| C: B plus branching on the flags | 1.71, 1.74 |
| D: all three removed | **0.99, 1.00** |

The copy chains are the biggest remaining cause. `EmitFloatTree`'s leaf arm
does `EmitLoadVar` (a resident's `movaps xmm0, xmm8+k`) and then
`movaps xmm<dst>, xmm0`. A store goes `movq rax, xmm2` (the bridge),
`movq xmm0, rax`, `movaps xmm8+k, xmm0`. All of it sits on the loop-carried
dependency path.

## Moves, gain and risk

1. **Promote the -O3 float residency and fusion to -O2.** Measured gain:
   mandelbrot 4.0x to 2.1x, nbody 2.2x to 1.6x. Risk: it changes the default
   codegen for every float program. It needs the O-lane's PROMISE (these
   numbers) and PROOF (Track T's full tier at -O3), and one pass at a time.
2. **Resident leaves and stores without the xmm0 hop.** Load a resident leaf
   straight into `xmm<dst>` (or use it as the operand), and store the root's
   `xmm2` straight into the resident when the target is one. Estimated gain at
   -O3: 2.1x to about 1.4x on mandelbrot (variant E). This is an estimate from
   the asm proxy, not a build. Risk: low and local. It is -O3 only, so -O2 and
   the self-host fixedpoint are untouched, but it helps the default only after
   move 1.
3. Branching on the flags for a float compare in a loop condition, and
   dropping the rax bridge at an assignment, are each worth about 0.1-0.2x
   here. They matter only after move 2.
