---
track: A
prio: 75
type: bug
blocked-by: []
summary: "`div`/`mod` picked signed-vs-unsigned division from the DIVIDEND alone, so every unsigned-over-signed division ran unsigned: `Word(40000) div SmallInt(-25536)` was 0 where FPC says -1, at all four widths, silently. The C side was wrong too — `uchar/schar`, `ushort/short` and `long/ulong` all disagreed with gcc."
status: done
owner: frank1-ACP
---

# An unsigned dividend made the whole division unsigned

- **Track A** (the shared signedness rule in `symtab.inc` and its six backend
  call sites; the operand normalisation is Track P's `parser.inc`).
- Found 2026-08-20 by an FPC differential probe over nested procedures and
  mixed-signedness arithmetic — one line of forty diverged.

## Repro

```pascal
var w: Word; si: SmallInt;
begin
  w := 40000; si := -25536;
  writeln(w div si, ' ', w mod si);   { FPC: -1 14464   pxx: 0 40000 }
end.
```

Every width was affected and every one of them silently:

| operands | expression | FPC | pxx |
| --- | --- | --- | --- |
| `Word` / `SmallInt` | `40000 div -25536` | -1 | 0 |
| `Byte` / `ShortInt` | `200 div -3` | -66 | 0 |
| `LongWord` / `Integer` | `3000000000 div -7` | -428571428 | 0 |
| `QWord` / `Int64` | `high(QWord) div -5` | 0 | 1 |

The boundary is sharp and is what named the cause: every case with a SIGNED
dividend agreed (`si div w`, `sh div b`, `i div c`), and the explicitly-cast
`Integer(w) div Integer(si)` was right. So it was not the division codegen — it
was which division the codegen was asked for.

## Cause

`TypeDivideUnsigned` read one operand:

```pascal
function TypeDivideUnsigned(dividend: TTypeKind): Boolean;
begin
  Result := TypeIsOrdinal(dividend) and not TypeSigned(dividend);
end;
```

Its comparison sibling four screens up, `TypeCompareUnsigned(lhs, rhs)`, has
read BOTH operands for two csmith fixes now. Two mechanisms for one concept —
"which signedness domain do these two operands live in" — and, exactly as
`normalise-dont-special-case.md` predicts, the one that was never given the
second operand is the one that stayed broken.

## Fix

One two-operand rule, one place, six consumers:

- `TypeDivideUnsigned(dividend, divisor)` answers per language. **Pascal
  converts by RANGE** — the pair widens to a type that holds both, which is
  signed the moment either operand is, so `LongWord div SmallInt` is signed even
  though the unsigned side is *wider* (Int64 holds both). **C converts by RANK**
  — at equal rank the unsigned operand wins and a sub-int pair promotes to
  signed int, which is what `TypeCompareUnsigned` already encodes, so C delegates
  to it rather than growing a third rule.
- `TypeDivideResult` takes the divisor too: the RESULT type carries the
  signedness, so without this `writeln(w div si)` would still have printed
  18446744073709551615 for a correctly computed -1.
- A positive literal divisor is normalised to unsigned in the parser
  (`NormalizeUnsignedDivLiteral`) instead of teaching the rule about literals.
  Pascal ranges a literal by its VALUE, so `q div 10` is unsigned while `q div n`
  with `n: Int64` is signed; retyping the operand keeps one rule serving the
  result type and all six backends. Without it every `QWord div <constant>` above
  2^63 would have gone negative — the regression this fix could most easily have
  shipped.
- The 32-bit backends' 64-bit PAIR path picked one signedness for the whole
  operation from "either operand is UInt64". That is the arithmetic/shift rule
  and it stays; `TypeBinop64Unsigned` routes only `div`/`mod` to the new rule, so
  `QWord div Int64` does not divide unsigned on i386/arm32/riscv32 while x86-64
  and aarch64 divide signed.

## The C half

Not a Pascal-only bug, though it was found from Pascal. Against gcc, the pinned
binary got three of fourteen lines wrong — `uchar/schar` and `ushort/short`
(C promotes both to `int`, so the division is signed) and `long/ulong` (C
converts the signed dividend to unsigned, so it is *unsigned* — the case where
the dividend-only rule erred in the other direction). All fourteen agree now.
C's existing `CTrunc32` normalisation in `cparser.inc` is untouched and still
carries the equal-rank 32-bit case.

## Gate

`test/test_div_mod_mixed_signedness.pas` — 35 assertions, every expectation
`fpc -O- -Mobjfpc` 3.2.2's: the four broken widths, the signed-dividend cases
that had to stay put, all-unsigned pairs, unsigned-over-positive-literal at
three widths, mixed widths, and two sign checks that pin the RESULT type rather
than just the bits. Wired into `make test`. `tools/gate.sh quick` GREEN,
self-host fixedpoint byte-identical, C probe identical to gcc.
