---
track: B
prio: 55
type: bug
blocked-by: []
summary: "IntToStr(q) where q: QWord >= 2^63 prints a NEGATIVE number — IntToStr(High(QWord)) answers -1 — because sysutils declares only IntToStr(Int64) and the QWord argument is passed through it. WriteLn(q) is correct, so the same value prints two different ways in one program. UIntToStr does not exist at all. Overload resolution on QWord vs Int64 already works, so this is purely two RTL functions."
---

# `IntToStr` of a QWord prints it signed

- **Type:** bug (**silent wrong VALUE** in ordinary formatting) — Track B
  (`lib/rtl/sysutils.pas`).
- **Status:** backlog
- **Opened:** 2026-08-21, from an integer-arithmetic differential against
  FPC 3.2.2 while working Track A.

## Symptom

```pascal
var u64: QWord;
begin
  u64 := QWord($8000000000000000);
  WriteLn('a writeln  : ', u64);            { 9223372036854775808  — correct }
  WriteLn('b inttostr : ', IntToStr(u64));  { -9223372036854775808 — wrong   }
  u64 := QWord($FFFFFFFFFFFFFFFF);
  WriteLn('c writeln  : ', u64);            { 18446744073709551615 — correct }
  WriteLn('d inttostr : ', IntToStr(u64));  { -1                   — wrong   }
end.
```

FPC prints the unsigned value in all four rows. `Cardinal` and `Word` are fine
in pxx — they widen into `Int64` losslessly — so only `QWord` at or above 2^63
is affected, which is exactly the range a hash, a checksum, a bitmask or a
64-bit id lives in.

The `WriteLn(u64)` row being *right* is what makes this nasty: the compiler's own
formatting knows the type, the library function does not, so one program prints
the same variable two different ways and neither call looks suspicious.

## Root cause

`sysutils.pas` declares one `IntToStr(value: Int64)`. A `QWord` argument is
accepted by it and reinterpreted as signed. There is no `IntToStr(QWord)`
overload and no `UIntToStr` at all (`UIntToStr(u64)` is a compile error:
`undefined variable (UIntToStr)`).

**Not a compiler gap.** Overload resolution on `QWord` vs `Int64` was verified
to work on 2026-08-21:

```pascal
function F(v: Int64): AnsiString; overload; begin Result := 'i64'; end;
function F(v: QWord): AnsiString; overload; begin Result := 'qw';  end;
{ F(q) -> 'qw', F(i) -> 'i64' on both fpc and pxx }
```

So adding the overload is sufficient; nothing in Track A needs to change.

## Fix

Two functions in `lib/rtl/sysutils.pas`:

- `function IntToStr(value: QWord): AnsiString; overload;`
- `function UIntToStr(value: QWord): AnsiString;` (and FPC also has the
  `Cardinal` shape) — FPC has it, and code that formats unsigned values
  explicitly reaches for it.

Both are the ordinary unsigned decimal loop; the existing `IntToStr(Int64)` body
is the model minus the sign handling. Watch the digit loop: `q div 10` on a
QWord must be the **unsigned** divide (pxx picks that from the operand type —
`u64 div 2` was verified correct in the same run).

## Gate

`make lib-test` green, plus the program above matching fpc 3.2.2 on all four
rows and `High(QWord)`/`High(Cardinal)`/`High(Word)` round-tripping.

## Note for whoever takes it

`High(QWord)` is itself refused by the compiler today
(`error: undefined variable (QWord)` inside `High(...)`), which is a separate
Track A gap — file it if you need it for the test, or write the literal.
