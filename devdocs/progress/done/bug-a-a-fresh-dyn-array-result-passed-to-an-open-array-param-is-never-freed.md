---
slug: bug-a-a-fresh-dyn-array-result-passed-to-an-open-array-param-is-never-freed
title: "A fresh dyn-array result passed to an open-array param leaks the whole array"
track: A
prio: 55
type: bug
status: done
found: 2026-09-02
found-by: frankB
owner: frankB
blocked-by: []
summary: "FIXED. `SumC(MkIA(i))` where `SumC(const a: array of Integer)` measured allocs=921 frees=0 — every array leaked WHOLE, not one element of it. An open-array parameter receives (data pointer, high), a RAW POINTER, and a dyn-array source already carries the [len][data] layout the param wants, so the handle went straight through with nothing retaining or releasing it. `const` and by-value alike, managed and non-managed element kinds alike. Same ownership family as the Copy/concat operands (ac02e5462) and the eight pointer seams before them; fixed with the same IRParkManagedDyn at the open-array argument in IRLowerCallArg. Named arrays, literal `[1,2,3,4]` and an already-owned `Copy(...)` were clean before and are unchanged after — the park returns its value untouched unless it owns a fresh +1. Measured live 1504 -> 7 with every sum identical."
---

# A fresh dyn-array result passed to an open-array param is never freed

## Measured

Each shape as its own program, 1000 trips, `-dPXX_ALLOC_CENSUS`:

| shape | allocs | frees | live |
| --- | --- | --- | --- |
| `SumC(MkIA(i))` — `const a: array of Integer` | 921 | **0** | **921** |
| `SumV(MkIA(i))` — by-value `a: array of Integer` | 921 | **0** | **921** |
| `CntS(MkArr(i))` — `const a: array of AnsiString` | 921 | **0** | **921** |
| `SumC(iv)` — NAMED array | 1 | 0 | 1 |
| `SumC([1,2,3,4])` — literal | 921 | 918 | 3 |
| `SumC(Copy(MkIA(i)))` — already owned | 1871 | 1868 | 3 |

`frees=0`, not "frees fewer than allocs". Nothing released these at all, and
passing an array to a routine is about as common a shape as Pascal has.

It leaks for `array of Integer` as well as `array of AnsiString`, so it is the
HANDLE with no owner, not the elements — the same signature as the Copy/concat
case.

## Why the existing test did not see it

`test_open_array_no_leak.pas` passes NAMED STATIC arrays
(`sa: array[0..2] of AnsiString`, `ia: array[0..2] of Integer`) a million times.
Those have an owner by construction, and the static-array arms in
`IRLowerCallArg` build their own owned dyn-array temp for the large case. The
leak needs a dyn-array RVALUE, which nothing in the corpus passed to an open
array. Not a duplicate, and not a gap anyone could have spotted by reading the
test's name.

## Fix

`IRLowerCallArg` (ir.inc), after the AN_COMMA unwrap so `argAST` is final and
after the static-array arms so they keep their own path:

```pascal
if (cpi >= 0) and (pathIdx >= 0) and (pathIdx < Procs[cpi].ParamCount) and
   Procs[cpi].Params[pathIdx].IsArray and (not Procs[cpi].Params[pathIdx].IsRef) and
   (NodeDynDepth(argAST) > 0) then
begin
  Result := IRParkManagedDyn(IRLowerAST(argAST), argAST);
  Exit;
end;
```

`IsRef` is excluded because a `var`/`out` open array must alias the caller's
array; a call result is not an lvalue and cannot reach that path anyway.

## Controls, and why they are the point

A park that fires too eagerly double-frees, so the three shapes that were
already clean matter as much as the three that leaked. `IRParkManagedDyn`
returns its value unchanged unless `IRNodeOwnsFreshCallResult` — so a named
array, a literal and an already-parked `Copy(...)` are untouched. All three
measured identical before and after, and every sum in the test is asserted
against the value measured BEFORE the fix, so a park that freed something still
in use shows up as a wrong number rather than only as a crash.

Regression test `test/test_open_array_fresh_result_leaks`, wired into test-core.
Positive control: live=1504 with the fix reverted, 7 with it, bound 50. Note the
value assertions pass EITHER WAY — `assert_no_leak.sh` is the row that catches
this, exactly as for [[bug-a-a-fresh-array-result-has-no-owner-as-a-copy-or-concat-operand]].

## Log
- 2026-09-02 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
