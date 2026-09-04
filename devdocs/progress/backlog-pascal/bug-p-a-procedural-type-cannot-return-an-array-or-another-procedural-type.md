---
slug: bug-p-a-procedural-type-cannot-return-an-array-or-another-procedural-type
track: P
prio: 30
type: bug
status: open
blocked-by: []
owner: unassigned
created: 2026-09-04
found-by: frankH (ProcRet* column census)
summary: "`TF = function(n: Integer): TIA` (dyn array), `: TA3` (fixed array) and `TOuter = function: TInner` (procedural) all parse as DECLARATIONS and then refuse at the call: `fp(3)[2]` and `fp(4)[2]` give `expected ')' before '['`, `fo()(41)` gives `expected ')' before '('`. FPC compiles all three (3 14 / 12 / 42). Cause is one thing, not three: ParseProcTypeSignature parses its return type with a bare ParseTypeKind, which cannot see an ARRAY return at all, so the six array columns (IsDynArray, DynDepth, FixedArrBytes, ArrAi, ElemTk, ElemRec) and ProcSig are never filled on the signature row -- and ApplyCallResultPtrSuffix reads exactly those to decide the suffix arm. The DIRECT-call spelling of each is measured working, so it is the signature path and not the feature."
---

# A procedural type cannot return an array, or another procedural type

Found 2026-09-04 by a census of the `ProcRet*` columns, not by a report. The
census was prompted by frankA after `ProcRetRecId` turned out to be the third
dropped field in a row in the same function, all three between the same two
existing comments.

## The census, and it is the useful part of this ticket

`ParseSubroutine` (the ordinary routine header, `pasparser_proc.inc`) fills all
17 `ProcRet*` columns. The three declaration paths in `pasparser_decl.inc` fill
the same 11 and drop the same 6:

| column group | reachable? | measured |
| --- | --- | --- |
| `EnumId` | **was LIVE** | fixed — prints the ordinal, not the member name |
| `RecId` (`ParseProcTypeSignature`) | **was LIVE** | fixed — selector at offset 0 |
| `RecId` (`ParseRecordMethodDecl`) | **NO** | `v.M(8).c` already answers 24 |
| `ProcSig` | **LIVE** | `fo()(41)` refused; FPC 42 |
| `IsDynArray` `DynDepth` `ElemTk` `ElemRec` | **LIVE** | `fp(3)[2]` refused; FPC `3 14` |
| `FixedArrBytes` `ArrAi` | **LIVE** | `fp(4)[2]` refused; FPC `12` |

The `RecId`-on-`ParseRecordMethodDecl` row is why the census was worth running
rather than reasoning about: it is a real asymmetry in the matrix and **not** a
defect, because a record method's row is filled again when its BODY goes through
`ParseSubroutine`. Only a routine that is declaration-ONLY — an interface
method — stays unfilled, which is exactly the row that was still wrong after the
`EnumId` reader was fixed.

## Repro

```pascal
type TIA = array of Integer;      TF1 = function(n: Integer): TIA;
     TA3 = array[0..2] of Integer; TF2 = function(k: Integer): TA3;
     TInner = function(k: Integer): Integer; TOuter = function: TInner;
```

`fp1(3)[2]` → `expected ')' before '['` · `fp2(4)[2]` → same · `fo()(41)` →
`expected ')' before '('`. FPC 3.2.2 `-Mdelphi` answers `14`, `12`, `42`.

**Each has a DIRECT-call control that passes**, which is what says this is the
signature path and not the feature: `Mk(3)[2]`, `Mk(4)[2]` and a direct chained
call all work today.

## Why it is one cause and not three

`ParseProcTypeSignature` parses its return type as a bare `ParseTypeKind`.
`ParseSubroutine` does not — it has a whole block ahead of that call which
recognises `array of T`, a named array type and a fixed array, and sets
`retIsDynArr` / `retArrAi` / `retElemTk` before the type name is consumed. The
signature path has none of it, so an array return type is not merely unrecorded,
it is **unparseable**: `mRetType` comes back as the ELEMENT kind with no way to
tell it from a scalar.

`ApplyCallResultPtrSuffix` then reads `ProcRetIsDynArray` / `ProcRetFixedArrBytes`
/ `ProcRetArrAi` to pick its suffix arm, finds a scalar, and declines — which is
the refusal above.

`ProcSig` is the cheaper half and may be separable: the column fill is one line
(the shape `ProcRetRecId` now uses), but `fo()(41)` also needs the parser to try
an argument list after a call whose result is procedural. `PasNodeProcSig`
(`pasparser_call.inc`) is the natural place — it answers "is this NODE a
procedural value" for AN_IDENT / AN_FIELD / AN_INDEX today and a call node is
the missing kind.

## Shape of the fix

Lift the array-return recognition out of `ParseSubroutine` so both paths share
it, rather than copying the block. That is the same normalisation the three
already-fixed columns wanted and did not get — this function has now produced
four dropped fields, which is the count `root-cause-over-microfix.md` calls a
design flaw rather than a smell.

## Gate

The three repros above with their direct-call controls, each **reading an
element or calling through**, never merely compiling: two of the three fixed
columns in this family turned a refusal into a silent wrong value when only half
the fix was in, so a compiles-or-not check certifies nothing here. Oracle: FPC.
