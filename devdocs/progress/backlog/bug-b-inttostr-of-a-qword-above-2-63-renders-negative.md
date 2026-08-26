---
slug: bug-b-inttostr-of-a-qword-above-2-63-renders-negative
track: B
prio: 55
status: backlog
---

# `IntToStr` of a QWord above 2^63 renders it negative

```pascal
uses SysUtils;
var q: QWord;
begin
  q := $8000000000000000;
  WriteLn(q);              { 9223372036854775808  — correct }
  WriteLn(IntToStr(q));    { -9223372036854775808 — WRONG }
end.
```

fpc 3.2.2 prints `9223372036854775808` for both. Every QWord with the top bit
set is affected, through every operator that produces one:

| expression (q = $8000000000000000) | pxx `IntToStr` | fpc |
| --- | --- | --- |
| `q` | -9223372036854775808 | 9223372036854775808 |
| `q or 1` | -9223372036854775807 | 9223372036854775809 |
| `q shl 63`, `q and …`, `q + 0`, `q * 1`, `q div 1` | negative | correct |
| `not QWord(0)` | -1 | 18446744073709551615 |

## Cause

`lib/rtl/sysutils.pas` declares exactly one overload:

```pascal
function IntToStr(value: Int64): AnsiString;
```

FPC declares `IntToStr(Value: QWord): string` alongside it. Without the QWord
arm the argument converts to `Int64` and the top bit becomes a sign.

**This is a missing overload, not an overload-resolution bug** — verified
separately: with both a `Sig(Int64)` and a `Sig(QWord)` declared in user code,
pxx picks the QWord arm for a QWord argument, and even for a `q shl 1`
expression. So adding the declaration is the whole fix.

Note the asymmetry that makes this easy to miss: `StrToQWord`, `StrToQWordDef`
and `TryStrToQWord` all exist in the same unit. Only the *rendering* direction
is missing. And `WriteLn(q)` is correct, so the value is right everywhere except
the one path most code uses to build a string.

## Fix

Add to `lib/rtl/sysutils.pas`, interface and implementation:

```pascal
function IntToStr(value: QWord): AnsiString;
```

rendering unsigned. FPC also has `UIntToStr` as an explicit spelling; worth
adding at the same time since it costs nothing once the digit loop exists.

Check whether `Format`'s `%d`/`%u` and `IntToHex` have the same gap before
closing — same unit, same shape of omission.

## Track

Track B: `lib/rtl/sysutils.pas` is B's file and the fix is an RTL declaration.
Filed from Track A, which found it but does not own the file. Build with
`$(PXX_STABLE)`; no compiler change is involved.

## Found by

An integer-arithmetic differential (34 programs). It surfaced disguised as a
shift bug — `IntToStr(u64 shl 63)` was the failing row — and only isolating
`IntToStr(u64)` on a plain variable showed the shift had nothing to do with it.
`WriteLn(u64 shl 63)` was correct all along.
