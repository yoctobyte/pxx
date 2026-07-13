---
prio: 45  # blocks ESP32 crypto eventually; not blocking any current target
---

# riscv32: p256field core-dumps (and bignum will not compile there at all)

- **Type:** bug / backend gap — **Track A** (riscv32 backend)
- **Status:** backlog
- **Opened:** 2026-07-12, found while taking `lib/rtl/p256field.pas` cross.

## Symptom

Two distinct riscv32 gaps, both in the crypto stack:

1. **`p256field` core-dumps.** After
   [[bug-64bit-named-const-truncated-32bit-targets]] was fixed, p256field is
   bit-exact on x86-64, aarch64, i386 and arm32 — but a riscv32 build segfaults
   under `qemu-riscv32`. Simple programs (e.g. `test/test_const64.pas`) run fine
   on riscv32, so it is something p256field does specifically: 64-bit locals,
   `array[0..5] of UInt64` frames, or the `var`-out-param 128-bit `MulAdd`.

2. **`bignum` does not compile for riscv32 at all**:
   `error: target: managed aggregate locals not yet supported`.
   (i386 rejects the same code with `only ordinal/pointer parameters supported
   yet` — a by-VALUE record param; see the notes below.)

## Why it matters

Not urgent for any target that ships today — 32-bit is perf-irrelevant and the
x86-64/aarch64 path is what pastella and the TLS stack use. It matters for the
**ESP32 story**: ESP32 targets are riscv32 and xtensa, and the pastella
killer-app demo (the same gossip protocol on a $3 chip and a laptop) needs realm
crypto to actually run on device. Field arithmetic is the first thing that has to
work there.

## Notes / where to start

- `p256field` uses only: `TFe = array[0..3] of UInt64` params (by-ref), a local
  `array[0..5] of UInt64`, `MulHiU64` (whose Pascal fallback is proven bit-exact
  on riscv32 by `test/lib_wideint.pas`), and 64-bit add/sub/compare (proven fine
  on i386, untested in bulk on riscv32).
- The i386 aggregate-param restriction lives at `compiler/parser.inc:17171`
  (`only ordinal/pointer parameters supported yet` — rejects by-value record
  params, which is what `bignum`'s `TBigInt` hits).

## Acceptance

- `test/lib_p256field.pas` runs green under `qemu-riscv32`, output identical to
  x86-64.
- (Stretch, separate slice) `bignum` compiles for riscv32/i386 — i.e. by-value
  record params and managed aggregate locals supported on the 32-bit backends.

## Reduced repro (2026-07-13) — it is NOT a crypto bug

The p256field core-dump is a symptom. The real defect is **much broader**: on
riscv32, **writes through a `var` array parameter do not work, for any element
type**. Reads are fine.

```pascal
program t;
type TI = array[0..3] of Integer;
procedure W(var r: TI);
begin
  r[0] := 11; r[1] := 22; r[2] := 33; r[3] := 44;
end;
var a: TI; i: Integer;
begin
  for i := 0 to 3 do a[i] := 0;
  W(a);
  for i := 0 to 3 do Write(a[i], ' ');   { riscv32 prints "0 0 0 0" — writes LOST }
  WriteLn;
end.
```

| case | riscv32 | i386 / x86-64 |
|---|---|---|
| **read** via `const` array param | correct | correct |
| **write** via `var` array param, `Integer` elems | **silently lost** (`0 0 0 0`) | correct |
| **write** via `var` array param, `UInt64` elems | **segfault** | correct |
| local array, direct writes (no param) | correct | correct |

So the indexed-lvalue address for a by-ref array param is wrong on riscv32 — the
write path does not dereference the parameter's pointer (it is the same shape as the
x86-64 `IR_LEA` skParam+IsRef special case in `ir_codegen.inc`, which the riscv32
backend appears to lack on the *write* side).

**Blast radius is far wider than crypto:** any RTL or user code that writes into a
`var` array param mis-executes on riscv32 — silently for 32-bit elements. Anything
riscv32/ESP32 should be treated as suspect until this is fixed.
