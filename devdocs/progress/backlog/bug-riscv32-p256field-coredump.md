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

## 2026-07-13: the blast radius is the WHOLE 32-bit crypto stack

This ticket is badly named. It is not a p256field bug. Measured today, with the
existing `test/lib_*` suites, no new code:

| test | riscv32 | arm32 | x86-64 / aarch64 |
|---|---|---|---|
| `lib_sha256` (SHA-256 + HMAC + HKDF) | **core-dump** | ok | ok |
| `lib_chacha20poly1305` | **core-dump** | **core-dump** | ok |
| `lib_p256field` | **core-dump** | ok | ok |

**An ESP32 cannot currently compute a SHA-256.** Not a signature — a *hash*. That
takes out HMAC, HKDF, the AEAD, and therefore any secure transport on the chip,
independently of ECDSA.

Prime suspect is the defect already reduced above: **writes through a `var` array
parameter are lost (32-bit elements) or crash (64-bit elements) on the 32-bit
backends.** SHA-256 and ChaCha are exactly that shape — a `var state: array[...]`
mutated in place — which fits the observed pattern, including why arm32 survives
SHA-256 (32-bit words) but dies on ChaCha.

**Consequence:** anything riscv32/xtensa/arm32 that touches crypto is broken today.
The ESP32 story (`examples/esp32/net-c3` proves *networking* works) does not extend to
anything sealed or authenticated.

Downstream: pastella's ESP32-capable sensor MVP is blocked on this — not on ECDSA
performance, and not on p256field.


## 2026-07-14 — RE-VERIFIED. Core defect stands; the ticket's BLAST-RADIUS theory is wrong.

Re-measured at HEAD. The reduced repro still holds and is the sharp statement of the bug:

    a `var` array parameter, indexed and WRITTEN, on riscv32 -> the writes are silently LOST
    (32-bit elements) or it segfaults (64-bit ones). i386 / arm32 / x86-64 are all correct.

So: **riscv32 has no deref-the-parameter-pointer path on the WRITE side of an indexed lvalue
for a by-ref array param.** That is the defect; it is real and it is riscv32-only.

Two corrections to what this ticket says:

- **"core-dumps" is stale.** `lib_p256field` no longer core-dumps on riscv32 — it now fails
  to COMPILE: `target riscv32: unsupported node in IR codegen: copy_rec_managed`. A second,
  separate riscv32 gap that the crash used to mask.

- **The "prime suspect covers arm32 too" reasoning is WRONG, and it was hiding a second bug.**
  Measured at HEAD:

    | target  | lib_sha256 | lib_chacha20poly1305 |
    |---------|------------|----------------------|
    | arm32   | **PASS**   | **SIGSEGV**          |
    | riscv32 | SIGSEGV    | SIGSEGV              |

  arm32 **passes** this ticket's own var-array-param repro, yet still segfaults on
  chacha20poly1305. Whatever breaks arm32 there is therefore NOT this defect. Filed
  separately as [[bug-arm32-chacha20poly1305-segfault]] — fixing riscv32 will not fix it,
  and anyone who assumed otherwise would have "fixed" arm32 by accident and moved on.

Scope of this ticket is now **riscv32 only**: the by-ref array-param write path, plus the
`copy_rec_managed` codegen gap it exposed.
