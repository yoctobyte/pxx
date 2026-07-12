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
