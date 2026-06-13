# Full Int64 codegen for i386

- **Type:** feature
- **Status:** done
- **Owner:** claude
- **Unblocks:** feature-cross-selfhost-i386
- **Opened:** 2026-06-13
- **Resolved:** 2026-06-13

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
- 2026-06-13 — DONE (commits 7756241 feat, 68bef67 fix). Replaced the low-dword
  model with an edx:eax value model: 64-bit const/load/store (sym + mem),
  add/sub/mul, and/or, full shl/shr (0..63), signed+unsigned div/mod (inline
  restoring long division, no RTL dep), neg/not, all six compares (signed and
  unsigned), 64-bit writeln, Int64 result return + param sign-extend home,
  syscall-result extension (errno sign- / address zero-extend), Trunc/Round
  sign-extend. Integer literals outside signed-32 range now type as Int64.
  New oracle test/test_i386_int64.pas in `make test-i386`; test / test-i386 /
  test-aarch64 / test-arm32 all green. Bugs fixed while landing: 64-bit
  eq/neq flag-clobber (`add esp` between `or` and `setcc`), signed divmod
  off-by-4 dividend abs, and (separate commit) the builtinheap `PWord = ^Int64`
  machine-word landmine that on i386 wrote 8 bytes into a 4-byte handle slot.
  Acceptance #1 (oracle in make test-i386) and #2 (cross_float matches) met;
  #3 (byte-identical self-host fixed-point) belongs to feature-cross-selfhost
  -i386 and is unblocked but not yet reached — see that ticket for the next
  wall (lexer/unit-dispatch token miscompile in the i386-hosted compiler).
