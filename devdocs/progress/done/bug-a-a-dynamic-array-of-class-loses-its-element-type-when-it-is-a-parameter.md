---
slug: bug-a-a-dynamic-array-of-class-loses-its-element-type-when-it-is-a-parameter
track: A
type: bug
prio: 80
status: done
created: 2026-09-06
found-by: frankD
owner: frank-coord-core
blocked-by: []
title: "`A[i].Field` on a dynamic array of CLASS reads garbage when the array is a PARAMETER — silent for a field, a heap dump for `var`, and `no such member` for a method"
summary: "A dynamic array whose ELEMENT is a class loses that element type when it arrives as a parameter. The same array as a global works. Records and scalars are unaffected. `A[0].Ext` returns a plausible wrong integer with NO diagnostic (by-value), reads arbitrary memory (`var`/open array), and `A[0].ClassName` errors `\"ClassName\": no such member on this record/class`. 20-line repro; fpc 3.2.2 prints the right answer for every row. Two of the three remaining errors on fcl-passrc `pparser.pp` (rung 7) are this one cause."
---

# A dynamic array of CLASS loses its element type when it is a parameter

- **Type:** bug (compiler core) — **Track A**. Silent wrong value, so prio 80.
- **Found:** 2026-09-06 by frankD, reducing the third wall of
  [[feature-pascal-corpus-expansion]] rung 7 (fcl-passrc).
- **Measured at** HEAD `b5f499d4a`, binary `67075a6033c8`.

## Repro — 20 lines, self-contained

```pascal
program p5;
{$mode objfpc}
type
  TEl = class Ext: string; end;
  TRec = record Ext: string; end;
  TArrC = array of TEl;
  TArrR = array of TRec;

procedure PC(A: TArrC);        begin WriteLn('named class : ', A[0].Ext); end;
procedure PR(A: TArrR);        begin WriteLn('named record: ', A[0].Ext); end;
procedure PV(var A: TArrC);    begin WriteLn('var class   : ', A[0].Ext); end;
procedure PK(const A: TArrC);  begin WriteLn('const class : ', A[0].Ext); end;

var ac: TArrC; ar: TArrR; e: TEl;
begin
  SetLength(ac,1); e := TEl.Create; e.Ext := 'cc'; ac[0] := e;
  SetLength(ar,1); ar[0].Ext := 'rr';
  WriteLn('global class: ', ac[0].Ext);
  PC(ac); PR(ar); PV(ac); PK(ac);
end.
```

| row | fpc 3.2.2 | pxx |
| --- | --- | --- |
| `global class` — same type, GLOBAL | `cc` | **`cc`** — correct |
| `named record` — element is a RECORD | `rr` | **`rr`** — correct |
| `named int` (separate probe) | `7` | **`7`** — correct |
| `named class` — by value | `cc` | **`4265192`**, no diagnostic |
| `var class` | `cc` | **dumps ~45KB of heap**, out-of-bounds read |
| `open array of TEl` | `cc` | **dumps heap** |
| `A[0].ClassName` | `TEl` | **`"ClassName": no such member on this record/class`** |

So the boundary is exact: **element is a CLASS *and* the array is a
PARAMETER.** Global-scope arrays of class are fine, and parameters whose
element is a record or a scalar are fine.

## Why the three symptoms are one defect

The element's CLASS identity is gone by the time `A[i]` is subscripted, so the
result is treated as an untyped/record blob:

- a FIELD read still resolves by offset and produces a plausible wrong value —
  **no crash, no diagnostic**, the shape CLAUDE.md calls the expensive one;
- a genuine class MEMBER (`ClassName`) has nowhere to resolve and reports
  `no such member`, which points at the member and not at the array;
- `var`/open array reach a different addressing path and read out of bounds.

Both fields of the two-field probe print the SAME wrong value, so it is the
element POINTER that is wrong, not a field offset.

## Lead — not confirmed, and it is a named one

[[refactor-p-a-parameters-own-kind-and-its-element-kind-are-one-field-and-the-name-says-neither]]:
`Procs[pi].Params[j].TypeKind` is the parameter's OWN kind when `IsArray` is
False and its ELEMENT kind when True. That ticket cleared the `pasparser_*`
increment and explicitly records **142 raw readers remaining in IR + lowering**
plus **12 sites annotated `suspect`**. A parameter of a named dynamic array of
class is exactly the shape where the two readings differ, so start with the
suspect list rather than with a fresh hypothesis. Its own ablation note is also
the warning: `ParamElemKind`'s refusal is load-bearing and removing it
segfaults `ifclist.pas` in a corpus `--tier quick` does not see.

## What it costs today

- **Rung 7, fcl-passrc `pparser.pp`:** two of the three remaining errors are
  this one cause — `CompareText(AUnitName, UsesClause[i].Name)` at
  `pparser.pp:3828`, where `TPasUsesClause = array of TPasUsesUnit` arrives as
  a parameter. The `.Name` lookup fails and the poison node types as Integer,
  which then produces a bogus `CompareText(AnsiString, Integer)` arity report.
  **Count causes, not errors.**
- **Generally:** `array of TSomeClass` as a parameter is an everyday Pascal
  shape and the by-value case is SILENT. Anything already relying on it is
  reading a wrong pointer and not being told.

## Coordinate warning for whoever takes it

Both errors were reported with `in: pscanner.pp` while the construct is in
`pparser.pp`, and the `near:` window was quoting pscanner text beside a
pparser LINE NUMBER. **`pscanner.pp` compiles CLEAN on its own** at this
binary, which is the cheap discriminator and how the misattribution was found.
Third arrangement of this corpus's coordinate problem — right line, wrong file
— after "stale `near:` across a unit boundary" and "line equal to the file
length". Grep the identifier across the corpus before trusting `in:`.

Also: the mangled suffix in `no overload of PeekOper$62774 matches` is **not
stable** — the same source at a different build printed `PeekOper$62727`. Do
not use it as a search key or a ticket title.

## Not caused by the fix that unmasked it

The three errors appeared only after
[[bug-p-a-parameterless-method-is-undefined-as-a-by-ref-argument]] and the
`ENotSupportedException` declaration removed the earlier walls. Isolated by
building the RTL fix WITHOUT the parser fix: all six errors are present
together, so these three are pre-existing and were hidden by a recovery
cascade, not introduced. Binary `0426b285ba35` for that arm.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
