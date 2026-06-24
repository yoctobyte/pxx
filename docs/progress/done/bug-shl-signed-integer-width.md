# bug: `shl` on a 32-bit Integer does not wrap at 32-bit width

- **Type:** bug (Track A — codegen width / FPC-parity)
- **Status:** done
- **Found:** 2026-06-23, differential sweep vs FPC
- **Severity:** low (loud, rare: only when shifting into/through bit 31 of a
  32-bit value). Sibling of the resolved `bug-shr-signed-integer-width`.

## Symptom

```pascal
var i: Integer;
begin i := 1; writeln(i shl 31); end.
{ fpc: -2147483648   (32-bit: 1 shl 31 = $80000000, signed)
  pxx:  2147483648   (64-bit: $0000000080000000, positive) }
```

pxx does `shl rax, cl` in a 64-bit register and never re-derives the 32-bit
result, so a value shifted into bit 31 keeps a zero sign-extension and reads
positive. `i shl 4` for `i = -1` similarly gives a wrong 64-bit value instead of
`-16`. Small shifts that stay within 31 bits are fine; 64-bit operands are fine.

## Why the obvious fix is unsafe (attempted + reverted 2026-06-23)

The shr fix's pattern — after the shift, re-derive rax from the low 32 bits when
`TypeSize(IRTk[left]) < 8` (cdqe for signed, `mov eax,eax` for unsigned) — makes
`i shl 31` correct, BUT it **regresses** the common 64-bit mask idiom
`UInt64(1) shl 40`, which then prints `0`. Root cause: the `UInt64(...)` /
`Int64(...)` typecast does not propagate an 8-byte `IRTk` to its operand node, so
`IRTk[left]` for `UInt64(1)` is understated to 32-bit and the truncation wrongly
fires. Over-truncation (a 64-bit mask becoming 0) is worse than the original
sign bug, so the change was reverted (only a doc-comment in `ir_codegen.inc`
`tkShl`/`tkIdent` remains, pointing here).

## Proper fix (ordered)

1. Make `Int64`/`UInt64` (and other explicit 64-bit) typecasts propagate
   `IRTk = tyInt64/tyUInt64` to the cast value node, so a width check on the
   operand is trustworthy. (Likely also helps other width-sensitive ops.)
2. Then re-apply the `tkShl` post-shift extend, gated on the operand width:
   `cdqe` for a signed <8-byte result, `mov eax,eax` for unsigned, nothing for
   64-bit. Add the cases to `test/test_shr_width.pas` (i shl 31 = -2147483648,
   -1 shl 4 = -16, Cardinal 1 shl 31 = 2147483648, Int64 1 shl 40 unchanged) and
   keep `UInt64(1) shl 40 = 1099511627776` passing.

## Repro

`var i:integer; begin i:=1; writeln(i shl 31); end.` (and the `UInt64(1) shl 40`
control that must stay `1099511627776`).

## Fix log

- 2026-06-24 — DONE on the 64-bit-register targets (x86-64 + aarch64). Two parts,
  in the order the ticket prescribed:
  1. **Width propagation (shared `ir.inc`, `AN_PTR_CAST`).** A builtin numeric
     reinterpret (`ASTIVal = -1`: Int64/UInt64/Integer/Cardinal/…) lowered to its
     inner expr's IR node and kept that node's IRTk, so `UInt64(1)` was understated
     to the 32-bit width of the `1` literal. Now re-tag the result IR node with the
     cast's `ASTTk` — the operand width becomes trustworthy for width-sensitive ops.
  2. **Post-shift wrap (`tkShl`).** After `shl`, when `TypeSize(IRTk[left]) < 8`,
     re-derive the narrow result from the low 32 bits: x86-64 `cdqe` / aarch64
     `sxtw x0, w0` for a signed operand, `mov eax,eax` / `mov w0,w0` for unsigned;
     64-bit operands (incl. the now-correctly-tagged `UInt64(...)` cast) shift
     as-is. i386/arm32/riscv32/xtensa use 32-bit registers for a 32-bit Integer, so
     the shift is naturally width-correct — no change.
- Test: extended `test/test_shr_width.pas` (i shl 31 = -2147483648, -1 shl 4 = -16,
  Cardinal 1 shl 31 = 2147483648, UInt64(1) shl 40 unchanged = 1099511627776,
  Int64(1) shl 52 = 4503599627370496), FPC oracle-matched on x86-64 and verified
  identical under qemu-aarch64. `make test` green + self-host byte-identical (the
  codegen change reseeds — fixed via `make bootstrap`).
