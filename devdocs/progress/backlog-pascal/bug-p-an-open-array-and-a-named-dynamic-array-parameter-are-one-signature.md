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

## The field the comparison is built from under-describes the signature

**`Procs[pi].Params[j].TypeKind` means two different things depending on
`IsArray`** — the parameter's own kind when False, its ELEMENT kind when True —
and the field name says neither. Verified 2026-09-06 at `pasparser_proc.inc`
around 1235: the named-array-type arm sets `tk := IntToTypeKind(ArrTypeElemTk
[paramAi])` and `isArr := True`, and `tk` is what reaches `ptypes[i]` and then
`Params[i].TypeKind`.

So the two declarations here are not merely *compared* as equal — they are
**stored** identically: same element kind, same `IsArray` bit. The signature
comparison is built from fields that under-describe the signature, which is why
adding one more comparison is the fix rather than correcting an existing one.

**frankD's suggestion, and it is better than a shared predicate:** the unit to
introduce is a **refusing accessor** — one that returns `tyUnknown` for an array
parameter's "own kind" — rather than a predicate both sides call. A predicate can
be called correctly and still be handed the wrong field; an accessor that refuses
cannot. Two open tickets read this same field without the `IsArray` guard
([[bug-p-a-default-value-is-accepted-on-an-open-array-parameter]] in the decl
path, and its call-path twin), so whoever takes any one of the three should
check whether the accessor closes all of them.

**What kind of defect this is, since it is not the one the summary shape
suggests.** Not a missing record: the column exists and is written. Not an
unread record: `ir.inc` reads it at the call site. It is a **partially-consulted
record** — one consumer reads it, another ignores it, and both produce
correct-looking code. An absence can in principle be enumerated (declared-set
minus carried-set); a column that one consumer reads and another does not cannot
be found by any set difference. The only question that surfaces it is *"what
distinguishes these two things, and is that thing consulted at the point where
they are distinguished?"*

## Neighbour

[[bug-p-a-distinct-type-declaration-is-parsed-but-is-not-distinct]] is the same
shape one type family over and its fix is the precedent for the two-sided
argument: it landed `AliasIdentityMismatch` as ONE predicate read from both
sides rather than a comparison written twice.

## Re-measured 2026-09-06 at compiler `3e54aadacbc8` (commit `886bfe597`)

Unchanged, and it reaches METHODS as well as free routines — measured, because
[[bug-p-a-named-array-type-parameter-was-a-scalar-wherever-no-implementation-header-repaired-it]]
(frankB, `d51037cf2`) landed in the four method parameter parsers the same day
and looked like it might interact.

```
free routine   empty=2 lit=2 named=2      fpc 1 1 2
class method   empty=2         named=2    fpc 1   2
```

**IT IS ORTHOGONAL, and the reason is worth stating because it is the opposite
of what I predicted.** I expected frankB's fix to EXTEND this bug to methods, on
the reasoning that a method's `a: TDyn` row used to be a scalar and so was
accidentally distinguishable from `array of LongInt`. It was already collapsing:
the warning fires at the IMPLEMENTATION HEADER (line 10 of the repro), which has
always gone through `ParseSubroutine` and its `FindArrayType` arm. frankB's fix
repairs the rows for the two spellings with NO implementation header — an
interface method and `virtual; abstract` — which is a population this bug never
reached in the first place. Neither fix moves the other.

So the fix here is still exactly where the summary says: `FindProcOverloadRec`
reading `ProcParamDynDepth` beside `Params[j].IsArray`, and the argument-side
matcher agreeing with it.
