# bug: `shl` on a 32-bit Integer does not wrap at 32-bit width

- **Type:** bug (Track A — codegen width / FPC-parity)
- **Status:** backlog
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
