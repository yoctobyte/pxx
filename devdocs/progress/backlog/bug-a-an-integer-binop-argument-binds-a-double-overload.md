---
track: A
prio: 40
type: bug
blocked-by: []
---

# An Integer-valued BINOP argument binds the Double overload, not the Integer one

- **Type:** bug (wrong overload chosen; silently different answer) — **Track A**
- **Found:** 2026-08-11 while fixing
  [[bug-a-an-integer-argument-binds-a-fixed-array-overload]] (which was hiding
  it: the array overload used to swallow the same call).
- **Pre-existing on `pinned`** (controlled).

```pascal
{$mode objfpc}
function Sum(x: Integer): Integer; overload; begin Sum := x * 10; end;
function Sum(x: Double): Integer;  overload; begin Sum := Trunc(x) + 1000; end;
var n: Integer;
begin
  n := 5;
  WriteLn(Sum(n));     { FPC 50   — pxx 50   }
  WriteLn(Sum(n + 1)); { FPC 60   — pxx 1006 }
  WriteLn(Sum(7));     { FPC 70   — pxx 70   }
  WriteLn(Sum(2.5));   { FPC 1002 — pxx 1002 }
end.
```

Only the BINOP row diverges: a plain variable and a literal both bind Integer,
`n + 1` binds Double. So the argument type an arithmetic expression reports is
not the one an exact match needs — presumably a widened kind (tyInt64 /
tyNativeInt) that misses the Integer parameter in Phase 1 and then lands in a
compatible phase where Double accepts it.

## Where to start

`MatchProcCall` in `symtab.inc`: Phase 1 is exact-only, and the compatible
phases that follow rank by fit. Either the binop's result kind should narrow
back to the operands' kind when both are Integer, or the compatible phase needs
to prefer an integer parameter for an integer-valued argument over a float one.
Measure the actual `argTypes[]` value for `n + 1` first — do not assume which
kind it is.

Related, same family: `project_overload_resolution_single_side_channel_entry`
(per-argument facts belong in the MatchArg* side channel, not in argTypes).

## Gate

The program above matching `fpc -O1`; `test/test_overload_array_vs_scalar.pas`
still green; self-host byte-identical.
