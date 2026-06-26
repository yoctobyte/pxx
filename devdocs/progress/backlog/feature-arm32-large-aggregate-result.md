# arm32: support record function results larger than 4 param words (sret)

- **Type:** feature (Track A — arm32 codegen / ABI)
- **Track:** A — `compiler/**`
- **Status:** backlog (filed by Track B)
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
