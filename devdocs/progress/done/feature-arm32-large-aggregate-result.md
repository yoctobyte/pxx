# arm32: support record function results larger than 4 param words (sret)

- **Type:** feature (Track A — arm32 codegen / ABI)
- **Track:** A — `compiler/**`
- **Status:** DONE (2026-06-30, Track A)
- **Owner:** — (Track A)
- **Opened:** 2026-06-25
- **Found-by:** [[feature-demo-raytracer]] — `Vec3 = record x, y, z: Double end`
  (24 bytes = 6 words) returned by value from `VAdd`/`VScale`/etc.
- **Relation:** sibling of [[feature-riscv32-record-function-results]] (done) —
  the same by-value-aggregate-result need, on a different cross target.

## Problem

The arm32 backend rejects a function whose result is a record bigger than four
machine words:

```
pascal26:49: target arm32: aggregate result with more than 4 param words not supported
```

Small aggregate results (≤4 words, returned in r0–r3) appear to work; a 6-word
`Vec3` does not. Per the AAPCS, a result larger than 4 bytes that is not a small
fundamental type is returned via the hidden first-argument pointer (sret): the
caller allocates space and passes its address in r0, the callee writes through
it. The backend needs that sret path for large aggregate results.

## Repro

```pascal
type Vec3 = record x, y, z: Double end;     { 24 bytes }
function VAdd(const a, b: Vec3): Vec3;
begin VAdd.x := a.x+b.x; VAdd.y := a.y+b.y; VAdd.z := a.z+b.z; end;
```

`pxx --target=arm32` fails at the `VAdd` declaration. Builds on x86-64 and
aarch64; checksum is cross-target identical there (x86-64 == aarch64).

## Impact

Any cross-arm32 build of code returning records bigger than 4 words — vector /
matrix / colour math, complex numbers, small value structs. Keeps the raytracer
demo (and similar value-style record APIs) off arm32 until implemented; the
portable host (x86-64) and aarch64 paths are fine.

## Done when

- The repro compiles for `--target=arm32` and runs correctly under qemu-arm.
- `examples/raytracer` cross-builds + runs on arm32 with the same checksum as
  x86-64 / aarch64.
- Regression test under the arm32 cross suite; self-host fixedpoint unaffected.

## Landed (2026-06-30, Track A)

Fix in `ir_codegen_arm32.inc` IR_CALL, the aggregate-result call path. The limit
was that this path always dropped the pushed arg words + hidden dest **before**
the call (`add sp, (j+1)*4`), which is only valid when every arg fits in r0–r3
(j ≤ 4) — so it bailed with `Error` for j > 4 rather than corrupt the callee's
stack arguments. Now:

- j ≤ 4: unchanged — load `r12` = hidden dest from `[sp + j*4]`, drop args+dest,
  call.
- j > 4: load `r12` = dest, then **keep the stack arg words (4..j-1) on the stack
  across the call** (sp still points at word j-1, exactly what the callee reads at
  `[fp + 8 + (pnWords-1-k)*4]`), call, and drop args+dest **after**. The hidden
  dest sits at `[sp + j*4]`, above word 0, so the callee's stack-param reads never
  collide with it. Mirrors the existing non-aggregate j > 4 path. Guard added for
  the 12-bit `ldr` offset (`j*4 >= 4096`).

The callee side already worked: `EmitAggregateDestStash` stashes `r12` in the
prologue (independent of the `[fp+8+...]` stack-param spill).

**Note — the ticket's `Vec3` repro is stale:** `const`/by-value record params are
passed **by reference** (1 word each) on arm32, so the raytracer's
`VAdd(const a,b: Vec3): Vec3` only makes j = 2 and already compiled. The real
trigger is an aggregate result with **> 4 argument words** from *scalars* (or
Int64/Double 2-word args), e.g. `function Make(p,q,s,t,u: Integer): R`. New test
`test/test_cross_aggregate_stackargs.pas` covers j = 5 (scalars), j = 7, mixed
Int64+scalar (5 words), and record-by-ref + scalars (5 words).

**Verified:** repros run correctly under qemu-arm (match x86-64); only arm32 had
the limit (i386 = all-stack args, aarch64/riscv32 = 8 register words);
`examples/raytracer` cross-builds on arm32 with output identical to x86-64; new
test in the arm32 cross suite; managed self-host byte-identical;
`make test` + cross (i386/aarch64/arm32/riscv32) green.
