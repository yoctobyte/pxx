---
track: A
prio: 55
type: bug
blocked-by: []
summary: "`Writeln(p - q)` where p, q are PChar segfaults: the pointer DIFFERENCE keeps pointer type in argument position, so Writeln renders the small integer as a PChar and dereferences it. Assigning the same expression to an Integer first works and gives the right value, so the arithmetic is fine — only the inferred type of the un-assigned result is wrong."
status: backlog
owner: unassigned
---

# PChar - PChar segfaults when passed straight to Writeln

Found 2026-08-25 by Track B while writing the FPC-differential test for the
`strings` PChar family (`feature-b-rtl-gap-inventory-22-sysutils-strutils-symbols`).
`StrECopy` returns a cursor into the destination buffer, and the natural way to
check it is `Writeln(StrECopy(d, s) - d)` — which is how this was hit.

## Repro (pdiff2.pas)

```pascal
program pdiff2;
var
  buf: array[0..15] of Char;
  a, b: PChar;
begin
  a := @buf[0];
  b := @buf[2];
  Writeln('diff=', b - a);
end.
```

| compiler | result |
| --- | --- |
| `fpc -O- -Mobjfpc` | prints `diff=2` |
| pxx (pinned stable, this checkout) | prints `diff=` then **segfaults** (exit 139) |

## The tell — the arithmetic is right, the TYPE is wrong

The identical expression assigned to an Integer first is correct:

```pascal
  d := b - a;          { d: Integer }
  Writeln('diff=', d); { prints 2 — correct on pxx }
```

So the subtraction computes 2. What goes wrong is the static type of the
un-assigned result: it stays PChar (or pointer), Writeln picks its
NUL-terminated-string overload, and dereferences address `2`. The assignment
case works only because the assignment's target type forces the conversion.

FPC/Delphi: `PChar - PChar` is a *ptrdiff*, an integer type, in every position —
not only when assigned.

## Why it matters beyond the print

The wrong inferred type is the bug; the crash is just the loudest symptom of
it. Any context that picks an overload from the expression's type — a `Writeln`,
an overloaded call, a `var` parameter — gets the pointer overload for a value
that is an integer. A crash is the cheap case; picking a different numeric
overload would be a silent wrong answer.

## Track B workaround in place

`test/lib_strings_pchar.pas` prints
`Integer(PtrUInt(p) - PtrUInt(@buf[0]))` instead. That is a TEST-side cast, not a
library reshape — no `lib/rtl` code was bent around this. Revert the cast to the
plain `p - @buf[0]` when this is fixed.

## Gate

Track A: `make compiler/pascal26` (self-host fixedpoint) + the repro above
printing `diff=2` and exiting 0.
