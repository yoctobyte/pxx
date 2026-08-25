---
track: P
prio: 55
type: bug
blocked-by: []
summary: "A dynamic-array-returning function's result loses its type when passed DIRECTLY as an argument: overload resolution sees `Pointer` instead of the array type and rejects the call. Assigning the same call to a variable of that type first works, so the function and the parameter are both fine — only the un-assigned result's inferred type is wrong. FPC compiles it."
status: backlog
owner: unassigned
---

# `Foo(MakeArray)` — a dyn-array result passed straight to a call types as Pointer

Found 2026-08-25 by Track B while adding `SplitString` to `lib/rtl/strutils.pas`
(`feature-b-rtl-gap-inventory-22-sysutils-strutils-symbols`). The natural way to
use it is `Dump(SplitString(line, ','))`; that is the shape that fails.

## Repro (nested3.pas)

```pascal
program nested3;
uses sysutils;

function Make: TStringArray;
begin
  SetLength(Result, 2);
end;

procedure Show(const tag: AnsiString; const v: TStringArray);
begin
  Writeln(tag, Length(v));
end;

begin
  Show('n=', Make);
end.
```

| compiler | result |
| --- | --- |
| `fpc -O- -Mobjfpc` | compiles, prints `n=2` |
| pxx (pinned stable) | **rejected** at compile time |

```
error: no overload of Show matches these arguments
  argument types: (ShortString, Pointer)
  candidates:
    Show(AnsiString, AnsiString)
```

Two things are visible in that message and they are separate: the *argument*
side reports `Pointer` where `TStringArray` was expected — that is the bug —
and the *candidate* side prints the `TStringArray` parameter as `AnsiString`,
which is a diagnostic-rendering problem on top of it.

## The tell — the function and the parameter are both fine

Assigning the identical call to a variable first compiles and runs:

```pascal
var a: TStringArray;
...
  a := Make;
  Show('n=', a);   { compiles, prints n=2 }
```

So `Make`'s return type, `Show`'s parameter type, and the dynamic array itself
all work. What is lost is the type of the call's result in *argument position* —
the assignment case succeeds only because the assignment's target type supplies
what inference did not.

Same shape as `bug-pchar-difference-in-writeln-arg-segfaults`, filed the same
session: an expression whose type is correct when a target forces it, and
degraded when nothing does.

## Reach

Any `f(g(...))` where `g` returns a dynamic array. That includes the whole
`SplitString` / `TStringHelper.Split` idiom, which is the ordinary way real FPC
code slices a line, so the wall is hit on the first realistic use.

## Track B workaround in place

`test/lib_strutils_words.pas` assigns each `SplitString` result to a local
before using it. Library code in `lib/rtl/**` was NOT reshaped — nothing there
passes a dyn-array result directly today, so no platonic code was bent.

## Gate

Track P: `make compiler/pascal26` (self-host fixedpoint) + the repro compiling
and printing `n=2`.
