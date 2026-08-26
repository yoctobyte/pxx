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

**RESOLVED 2026-08-26 — already fixed when re-measured, and the re-measurement
found two live bugs beside it. See Outcome at the end.**

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


---

## Outcome (2026-08-26)

**The filed symptom no longer reproduces.** The ticket's own `nested3.pas`
compiles and prints `n=2`, and so does every widening of it I could construct:
a user-defined `array of Integer`, by-value and `const` parameters, an
array-returning call used as `Length()`'s operand, subscripted directly
(`MakeI[1]`), and `Dump(SplitString(line, ','))` — the shape the ticket was
filed from. Fixed by something between 2026-08-25 and now; no commit here
claims it, so it went with a change that did not know it was the fix.

Left `blocked-by: []` and moved as resolved rather than deleted, because the
measurement below is the reason it was worth reopening at all.

## What the re-measurement DID find

Widening the repro to an overload SET — which the original error message
(`no overload of Show matches`) pointed at — turned up two live bugs, both
silent, both with no diagnostic, and both the same root cause as each other:
pxx presents an array's ELEMENT kind as its type kind, so an array parameter
and a scalar parameter of that element type are indistinguishable to overload
resolution, which then takes whichever was DECLARED FIRST.

| call | overloads, in declaration order | fpc | pxx (before) |
| --- | --- | --- | --- |
| `P('hello')` | `P(array of AnsiString)`, `P(AnsiString)` | `str hello` | **`arr 5`** |
| `S(ia)` | `S(v: Integer)`, `S(const v: TIA)` | `Sarr 4` | **`Sint 1440743456`** |
| `T(fa)` | `T(v: Integer)`, `T(const v: TFA)` | `Tfix 11` | **`Tint 4303792`** |

The last two are the dyn-array handle and the variable's address, printed as
integers. Writing the same two overloads the other way round gives the right
answer in every case, which is exactly why this had gone unnoticed.

`bug-a-an-integer-argument-binds-a-fixed-array-overload` had already fixed one
quarter of this — an ordinal argument against an array parameter — via the
`MatchArgScalar` channel. Both remaining directions are now fixed beside it:
strings joined that channel, and a new `MatchArgArray` channel covers the
mirror (a definitely-array argument cannot bind a scalar parameter). The two
are deliberately NOT each other's negation: every uncertain argument shape
stays False in both, or it would be blocked from every candidate at once.

Pinned in `test/test_array_and_scalar_overload_binding.pas`, both directions,
including the reversed-declaration pairs that were always right.

## The diagnostic half is still open

The ticket also noted that the candidate list printed a `TStringArray`
parameter as `AnsiString`. That is the same element-kind-is-the-type-kind
convention showing through `OverloadReport`, and it is still true — a
diagnostic-rendering problem, not a miscompile, so it is left where the
FPC-parity ceiling puts it.
