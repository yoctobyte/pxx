---
track: A
prio: 65
type: bug
---

# A decimal literal wider than Int64 WRAPS silently

Found by differential-testing the promotable int against CPython 2026-07-20.
Pre-existing and independent of that feature.

## Repro

```pascal
program p;
var x: Int64;
begin
  x := 9258932120814846640;
  Writeln(x);
end.
```

pxx prints `-9187811952894704976`. FPC rejects the program: `Error: Number
9258932120814846640 is out of range for Int64`.

## Cause

`compiler/lexer.inc`, the decimal branch of the number scanner:

```pascal
while (SrcPos <= Length(Source)) and (Source[SrcPos] in ['0'..'9']) do
  begin n := n*10 + (Ord(Source[SrcPos])-48); Inc(SrcPos); end;
```

`n` is an Int64 and the accumulation wraps with no check. The hex (`$`) branch
a few lines below has the same shape and the same hole.

## Why it matters

It is a silent wrong VALUE from a constant the programmer wrote out in full —
the least suspicious thing in a program. There is no diagnostic and no runtime
trap, and `{$Q+}` does not help because nothing overflows at runtime; the wrong
value is baked in at lex time.

## Shape

Detect before multiplying — `n > (High(Int64) - digit) div 10` — and error with
the literal text and the target type, matching FPC's wording. Decide what to do
about a literal that fits UInt64 but not Int64 (`18446744073709551615`), which
FPC accepts in a QWord context; that is the one case that needs thought rather
than a flat range check.

## Gate

`{%FAIL}`-style tests for decimal and hex over-range literals, the UInt64-range
case still accepted where FPC accepts it, `--tier quick` + self-host
byte-identical.
