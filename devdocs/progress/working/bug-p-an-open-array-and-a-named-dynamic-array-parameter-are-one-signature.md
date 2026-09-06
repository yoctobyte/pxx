---
track: P
prio: 25
type: bug
blocked-by: []
summary: "`procedure P(a: array of LongInt)` and `procedure P(a: TLongIntArray)` were ONE signature in pxx and are two overloads in fpc. FIXED for every binding fpc's own row exercises: `FindProcOverloadRec` now reads `ProcParamDynDepth` beside `Params[j].IsArray` (both sides must be array params; a dyn depth is only ever ASSERTED, so 0 on both sides of a forward/body pair is today's answer and no split), and the argument side gained two channels — `MatchArgDynDepth` (this argument is certainly a named dynamic array) and its MIRROR `MatchArgOpenCtor` (certainly an anonymous element list), read by `MatchParamExact` so they RANK and never refuse. tarrconstr6 burned. STILL OPEN, and measured: `Test(Nil)` takes whichever overload is declared FIRST (1 open-first, 2 dyn-first) where fpc always binds the dynamic one. Arms written in `MatchParamExact` and `MatchArgNilOk` did NOT fire and were removed. THE PHASE IS NOW IDENTIFIED (2026-09-06): `MatchParamCompatible` is `TypesCompatible(...) or MatchArgNilOk(...)`, pxx short-circuits `or` (FPC's {$B-}), and `TypesCompatible` already answers TRUE for an array parameter against nil's tyPointer — so the FIRST candidate is granted outright and the named-dyn one is never asked. That is also why `a.nilarg` printed nothing: the trace sits BELOW the short-circuit. The residual is a ranking that does not exist rather than one that ranks wrong, so the fix belongs in the compatible phase, not in `MatchParamExact`."
status: working
owner: frankS
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

## Fixed 2026-09-06 (frankS) — three channels, and one control did the work

Measured at compiler `630fb424c66c`. `tarrconstr6.pp` exits 0 with no
`duplicate definition` warning; `test_an_open_array_and_a_named_dynamic_array_are_two_overloads`
is byte-identical to fpc 3.2.2 on every row.

**Registration.** `FindProcOverloadRec` gained a `pdyn` array and a fifth arm,
after the record / string-width / alias / pointer four. It splits (0, N) rather
than requiring both sides positive the way the pointer arm does, because a dyn
depth is only ever ASSERTED and never denied — 0 is not a sentinel here the way
`tyUnknown` is there. What keeps it from failing open is the pair of `IsArray`
tests: a non-array parameter's 0 says nothing about arrays, and a declaration
path that forgot the column leaves 0 on BOTH sides of its own forward/body pair.

**Argument side, two channels and not one.** `MatchArgDynDepth` (certainly a
named dynamic array) and `MatchArgOpenCtor` (certainly an anonymous element
list) — two, for the reason `MatchArgScalar` and `MatchArgArray` are two: 0 in
the first means "not certain", so reading its absence as an assertion would
block an unrecognised shape from every candidate at once. Both read by
`MatchParamExact`, so they RANK and never refuse: `OnlyOpen(la)` with a dyn
argument and only an open candidate still binds, which is ordinary Pascal.

**`TDynArr.Create(1,2,3)` and `[1,2,3]` are both an `AN_ARRAY_CTOR` by the time
the matcher sees them**, and the retag loses the difference (depth 1 encodes
`ASTSOffset` as 0, exactly what an anonymous list gets). New AST column
`ASTCtorDynDepth`, stamped in the one arm that still knows a type name was
written — its own column rather than a third meaning in the `ASTSOffset`/
`ASTSLen` union, whose key was not chosen for that question.

### The row that earned its place

The first version ranked a dyn ARGUMENT away from the open parameter and was
correct on **every row of the repro in this ticket**. Written the other way
round, `Test([])` and `Test([1,2,3])` answered 2 where fpc answers 1: the
element-list direction still tied and the exact phase took the first candidate
in the chain. **One source order cannot tell a rule from an accident of
declaration order**, and this ticket's own repro happened to be written in the
order that hides half the bug. Both orders are now in the fixture, under two
type names.

### The `nil` residual, and why nothing was written for it

fpc binds `Test(Nil)` to the dynamic overload — an open array is a
(pointer, high) pair with no nil state. pxx takes whichever is declared first.
Arms written in `MatchParamExact` and in `MatchArgNilOk` **both failed to
fire**, and `PXXDBG=a.nilarg` shows no trace line for a nil argument against an
array parameter in either the one- or the two-candidate program: the call is
resolved in an earlier phase that has not been identified. Both arms were
REMOVED rather than left in place — dead code that reads as live is worse than
an open gap — and each site now carries a comment saying what was measured.
Whoever takes this starts by finding that phase, not by writing a third arm.

## The phase, measured — 2026-09-06 (frankS), compiler `4b22a668e6ab`

frankB asked the right question about the earlier evidence: was `PXXDBG=a.nilarg`
a trace point I added, or one that already existed? It already existed
(`de4693979`, 2026-08-21), and it sits after three early bails inside
`MatchArgNilOk` — so its silence was weaker evidence than I read it as. That
caution is what produced the finding.

A temporary trace placed AHEAD of the `or` in `MatchParamCompatible`
(symtab.inc), on the two-candidate program:

```
PXXDBG a.nilarg PRE Test param 0 paramtk=11 argtk=17 isarray=TRUE proc#=136 dyndepth=0 typescompat=TRUE
```

**Exactly one line, and `dyndepth=0` names it as the OPEN-array candidate.**
`TypesCompatible` answers TRUE, the `or` short-circuits, `MatchArgNilOk` is
never CALLED — a different fact from being called and bailing, and the one a
reader needs. The named-dyn candidate is never asked at all.

Oracle, both declaration orders (fpc 3.2.2 vs pxx `4b22a668e6ab`):

```
open-first   fpc: dyn  0     pxx: open 0
dyn-first    fpc: dyn  0     pxx: dyn  0
```

So fpc binds the named dynamic array in BOTH orders and pxx binds by
DECLARATION ORDER — the same axis that made the first version of this ticket's
fix look complete on one source order.

**What this changes about the fix.** There is no ranking between two array
shapes for a nil argument to lose: the compatible phase grants the first
candidate and stops. An arm in `MatchParamExact` cannot fire because the call
never gets that far. Whoever takes this is adding a preference where today there
is a first-hit, which is a different and larger change than the two channels
this ticket already landed — and it is the same shape as the residual on
[[refactor-a-the-assignment-kind-funnel-needs-a-third-discriminator-not-a-third-special-case]]:
a coarse kind channel granting a match the finer channel would have declined.

Not taken here. frankB said they would take the nil row if their group surfaced
the phase; the phase is above, and this ticket stays free.
