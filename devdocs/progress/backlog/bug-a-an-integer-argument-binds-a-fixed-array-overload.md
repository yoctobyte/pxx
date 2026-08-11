---
track: A
prio: 45
type: bug
blocked-by: []
---

# An Integer argument binds the fixed-ARRAY overload, not the Integer one

- **Type:** bug (wrong overload chosen; surfaces as a nonsense diagnostic) —
  **Track A**
- **Found:** 2026-08-11 while fixing
  [[bug-a-a-fixed-array-call-result-is-refused-as-a-const-byref-argument]].
- **Pre-existing on `pinned`** (controlled).

```pascal
{$mode objfpc}
type TArr = array[0..2] of Integer;
function Sum(const a: TArr): Integer; overload; begin Sum := a[0]+a[1]+a[2]; end;
function Sum(x: Integer): Integer;    overload; begin Sum := x*10; end;
begin WriteLn(Sum(7)); end.
```

FPC prints `70`. pxx refuses:

```
error: by-reference argument must be a variable
```

The diagnostic names the by-ref check, which is the SYMPTOM: overload
resolution has already bound `Sum(7)` to the ARRAY overload, and the by-ref
check then correctly observes that an integer literal is not an lvalue. The
bug is one step earlier.

## Likely mechanism (not yet confirmed — measure before believing it)

`Procs[].Params[i].TypeKind` for a fixed-array parameter carries the ELEMENT
kind (the same conflation that made `function F: TArr` look like an Integer
result — `bug-a-set-and-array-function-results-come-back-empty`), so to the
matcher `const a: TArr` and `x: Integer` present the SAME parameter type and
the array one wins by declaration order. If so, the fix belongs in the single
side channel into `MatchProcCall*` (see
`project_overload_resolution_single_side_channel_entry`): the matcher needs
`Params[i].IsArray` to disqualify a scalar argument, not a new argTypes value.

Check the sibling shapes in the same pass — a SET parameter and a frozen
`string[N]` parameter are the other two whose Params[].TypeKind is not the
whole story.

## Gate

The program above printing `70`, plus the array overload still selected for a
real `TArr` argument and for a `TArr`-returning call result
(`test/test_aggregate_function_results.pas`'s `arr as arg` row); self-host
byte-identical.
