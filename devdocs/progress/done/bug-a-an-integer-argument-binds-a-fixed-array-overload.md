---
track: A
prio: 45
type: bug
blocked-by: []
status: done
owner: claude-A
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

## Resolution (2026-08-11)

Worse than the ticket recorded: only the LITERAL form is refused. `Sum(n)` with
`n: Integer` **compiles and segfaults** — an identifier satisfies the by-ref
check, so the array overload is entered and reads three elements off a 4-byte
variable.

Fixed in the matcher, via the existing per-argument side channel rather than
through `argTypes` (which cannot carry it — a fixed array's element kind IS its
argTypes entry): a new `MatchArgScalar[j]`, filled beside `MatchArgRec` in
`MatchCallDelphiProcAddr`, marks an argument whose scalar-ness is CERTAIN (an
ordinal/float literal, an arithmetic expression, a non-array variable, or a
scalar-returning call). `MatchArgRecMismatch` — already consulted by every match
phase — disqualifies an array parameter for such an argument. `array of const`
(tyRecord/tyVariant element) and untyped parameters are excluded, and anything
whose shape is not certain stays unmarked and matches exactly as before.

Verified against `fpc -O1`: array variable, fixed-array-returning call, scalar
variable, literal and float all pick what FPC picks; open-array and
`array of const` overloads, `SetLength`d dynamic arrays and `Format` unaffected.
Family sweep of all 132 `test/*.pas` matching overload|array|param, HEAD vs
`pinned`: no regression — the only three diffs are tests `pinned` cannot build.

New `test/test_overload_array_vs_scalar.pas`.

One divergence surfaced that this bug had been hiding — `Sum(n + 1)` binds a
`Double` overload where FPC binds `Integer`. Pre-existing on `pinned`, filed as
`bug-a-an-integer-binop-argument-binds-a-double-overload`.

## Log
- 2026-08-11 — resolved, commit 76a798ba3.
