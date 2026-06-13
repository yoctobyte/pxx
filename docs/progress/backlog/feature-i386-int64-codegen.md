# Full Int64 codegen for i386

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Unblocks:** feature-cross-selfhost-i386
- **Opened:** 2026-06-13

## Problem

The i386 backend still has a low-dword scalar model for many 8-byte values.
That has now shown up in multiple unrelated-looking places during the
cross-self-host burn-down:

- `shr 32` on small `Int64` values duplicated or lost the low dword.
- ELF/header/data/string-table 64-bit serialization needed local small-value
  guards.
- Float literal and float-writer constants lose their high dword under an
  i386-hosted compiler.
- Large integer constants, shifts, boolean comparisons over widened values,
  pointer-sized serialization, and memory writes are all at risk because the
  backend does not consistently keep `(lo, hi)` pairs for `Int64`/`UInt64`.

The latest i386 fixed-point probe terminates, but differs at byte 24194 because
the i386-hosted compiler emits zero for the double bits of
`1000000000000000.0` (`0x430c6bf526340000`) in generated x86-64 float-writer
code.

## Scope

- Define an explicit i386 value model for `Int64`/`UInt64`, likely EDX:EAX for
  expression results plus paired stack/local stores.
- Implement 64-bit load/store, constants, `shl`/`shr`/`sar`, arithmetic needed
  by the compiler, comparisons, and argument/return handling.
- Replace local serialization workarounds where the general model makes them
  unnecessary.
- Add focused i386 oracle tests for:
  - `Int64` shifts by 0, 1, 31, 32, 40, 63.
  - high-dword constants and memory stores/loads.
  - comparisons and boolean results involving high dwords.
  - float literal bit patterns emitted by an i386-hosted compiler.

## Acceptance

- `make test-i386` includes focused 64-bit oracle coverage and passes.
- i386-hosted `test/test_cross_float.pas --target=i386` matches native output.
- `feature-cross-selfhost-i386` fixed-point probe reaches byte-identical
  compiler output without ad hoc `shr 32` workarounds.

## Log

- 2026-06-13 — opened from the i386 self-host burn-down. The repeated failures
  are no longer isolated bugs; they point to missing first-class 64-bit scalar
  support in the i386 backend.
