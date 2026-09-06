---
track: P
prio: 45
type: bug
blocked-by: []
summary: "`procedure P(a: array of LongInt)` and `procedure P(a: TLongIntArray)` are two overloads in fpc and ONE signature in pxx. `FindProcOverloadRec` compares `Params[j].IsArray`, a single bit, and never reads `ProcParamDynDepth` — the column that ALREADY records the difference and that ir.inc ALREADY branches on at the call site. So the second declaration is written into the first's row, pxx warns `duplicate definition ... the later body wins`, and every call to EITHER runs the later body. The registration side alone is not the fix: this arm and the argument-side matcher must agree, or a call is refused against a candidate list the right candidate was never in."
status: backlog
owner: unassigned
---

# An open-array and a named dynamic-array parameter are one signature

- **Found:** 2026-09-06 (frankS), burning `tarrconstr6.pp` from the FPC-testsuite
  corpus ([[feature-pascal-corpus-fpc-testsuite]]). The row's OTHER half — the
  `TLongIntArray.Create(...)` constructor — is fixed and its twin `tarrconstr1`
  is burned; this is what the file reaches next.
- **Measured at compiler `aa3669390683`** against fpc 3.2.2, which accepts the
  program and exits 0.

```pascal
type TLongIntArray = array of LongInt;
function Test(aArr: array of LongInt): Integer; begin Test := 1 end;
function Test(aArr: TLongIntArray): Integer;    begin Test := 2 end;
var la: TLongIntArray;
begin
  la := Nil;
  if Test([])                       <> 1 then Halt(1);   { pxx: 2 }
  if Test([1, 2, 3])                <> 1 then Halt(2);
  if Test(TLongIntArray.Create(1,2,3)) <> 2 then Halt(3);
  if Test(la)                       <> 2 then Halt(4);
end.
```

pxx prints `duplicate definition of 'Test' with the same parameter types; the
later body wins` and halts 1.

## The column already exists — nothing reads it here

`ProcParamDynDepth[proc * MAX_PROC_PARAMS + j]` is `> 0` for a named
dynamic-array parameter and `0` for an open `array of T`, and its own comment in
`defs.inc` says it exists to *"distinguish a resizable `TDynArr = array of T`
param from an open `array of T` param at the call site"*. `ir.inc` branches on it
in four places. `FindProcOverloadRec` (`symtab.inc`) compares
`Params[j].IsArray`, which is `True` for both.

So this is not a missing fact. It is a fact recorded, consumed by the lowering,
and never consulted by the thing that decides whether two declarations are the
same routine.

## Why the one-line arm is not the whole fix

`FindProcOverloadRec` already carries four arms of exactly this shape — records,
string element width, distinct type aliases, pointer pointees — and a fifth
reading `ProcParamDynDepth` is mechanical. **The warning above that block is the
reason it is not enough:**

> THIS ARM AND `MatchArgRecMismatch`'S MUST AGREE ... a permissive answer here
> with a strict one there means a call is refused against a candidate list that
> never had the right candidate in it.

Splitting the rows creates two candidates for `Test`. The argument side must then
rank them, and the ranking is the part that has no precedent here: `[1, 2, 3]` is
an open-array constructor and must prefer the open-array parameter, while a
variable of the named type must prefer the named one. **`Nil` binds only the
dynamic one** — fpc rejects `Test(Nil)` against an open array — which is a third
rule and the one most likely to be missing.

The pointer arm's guard is the right model for the registration side:
**both sides must positively name a depth.** A path that never wrote the column
leaves 0, which reads as "open array" — the same answer it gives today — so this
arm can only ever SPLIT a pair where one side positively recorded a dynamic
depth, and cannot turn a missing write into a phantom overload. That direction is
safe; the argument side is where the work is.

## Gate

`tarrconstr6.pp` exits 0 with no `duplicate definition` warning, plus a test
asserting all four bindings by VALUE (not by exit code — the corpus runner judges
by exit code and this defect is a wrong-value defect that halts, so an
exit-clean row would not have caught the first three cases had `Halt` been
absent).

## Neighbour

[[bug-p-a-distinct-type-declaration-is-parsed-but-is-not-distinct]] is the same
shape one type family over and its fix is the precedent for the two-sided
argument: it landed `AliasIdentityMismatch` as ONE predicate read from both
sides rather than a comparison written twice.
