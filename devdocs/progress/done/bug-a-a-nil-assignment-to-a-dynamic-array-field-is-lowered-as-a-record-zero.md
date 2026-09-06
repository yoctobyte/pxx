---
track: A
prio: 50
type: bug
blocked-by: []
status: done
owner: frankD
created: 2026-09-06
summary: "`Fld := nil` on a dynamic-array FIELD was two stacked defects and the first was hiding the second. (1) AssignSideKind's field/element/deref arm typed the node as its ELEMENT — an array's TypeKind IS the element's — so an `array of <record>` field was REFUSED as `cannot assign Pointer to record`; the AN_IDENT arm has bailed on `Syms[si].IsArray` since it was written and this arm never got the equivalent. (2) With the false reject gone the program SEGFAULTED: ASTNodeIsWholeArray answered only for the AN_IDENT spelling, so the field took ir.inc's `record-shaped destination := nil` arm and zeroed RecSize(ELEMENT) = 4 bytes over the 8-byte array handle, and the next Length() read a truncated pointer. ACCIDENTAL COVER — the refusal meant nothing ever reached the bad lowering, so neither defect is provable alone and a false REJECT was load-bearing. fcl-passrc pastree.pp:5817 (`Fields := nil` in TRecordValues.Destroy) is the live case. FIXED 2026-09-06, both halves in one commit."
---

# A nil assignment to a dynamic-array field is lowered as a record zero

- **Type:** bug (miscompile + false reject) — **Track A** (`compiler/ir.inc`,
  `compiler/symtab.inc`).
- Found in fcl-passrc rung 7, [[feature-pascal-corpus-expansion]].

## The boundary

```pascal
var  ra: array of TR;   ra := nil;     { plain VARIABLE  — always worked  }
TC.IA: array of Integer; IA := nil;    { scalar element  — always worked  }
TC.RA: array of TR;      RA := nil;    { record element  — refused, then crashed }
```

fpc 3.2.2 `-Mobjfpc` sets length 0 for all three.

## The two defects, and why the order matters

**1. The false reject.** `AssignSideKind` reads the destination's kind off
`ASTTk[node]`, and for a dyn-array field that is the ELEMENT's kind. The
`AN_IDENT` arm bails on `Syms[si].IsArray` with the comment *"the kind is the
ELEMENT's"*; the arm added later for fields, elements and derefs never got the
same bail. So the check described an `array of TR` destination as a `record`
and refused legal Pascal — the direction that function's own header calls the
worse one: *"a false REJECT of working code is a worse defect than the false
accept being fixed here."*

**2. The miscompile underneath it.** `ASTNodeIsWholeArray` opens by explaining
that an array's TypeKind is its element's and that a pass deciding from the
kind alone *cannot tell `arr := other` from `arr[i] := other`* — and then
answers only for `AN_IDENT`. A dyn-array field is a whole array and it said no,
so the store took the "any record-shaped destination := nil" arm: zero-fill
`RecSize(TR)` = 4 bytes at the field's address, over an 8-byte array handle.

## ACCIDENTAL COVER — the part worth carrying

**The type error was a refusal, so nothing had ever reached the bad lowering.**
Fixing the false reject is what exposed the segfault; had they been worked in
the other order the crash would have looked like a regression introduced by the
whole-array widening. Neither is provable alone, which is why both are in one
commit.

The general shape: **a false reject can be load-bearing.** "We refuse this legal
construct" is not a bounded cost — behind it sits an unknown amount of lowering
that no instrument has ever exercised, and the refusal is what keeps it off
every one of them.

## Resolution 2026-09-06

- `AssignSideKind`'s AN_INDEX/AN_FIELD/AN_DEREF arm bails on
  `NodeDynDepth(node) > 0` — the shared answer, not a fresh walk: it already
  types fields, elements, derefs, calls, `Copy` and array constructors.
- `ASTNodeIsWholeArray` gained the `AN_FIELD` arm via `RecFieldIsArray`, and
  **moved** to the end of `symtab.inc` because that arm needs `ResolveNodeRec`
  and `GetASTIdentName`, both defined later in the file. Its only caller is in
  `ir.inc`, included after all of it; the FPC seed canary in `gate.sh quick`
  covers the move.

## The fixture

`test/test_nil_assigned_to_a_dynamic_array_field.pas`, byte-identical to fpc.
The `int` and `out` rows already worked and are present so the file cannot read
"arrays now work" as "records now work". **The `mp` row must not move**: a
method-pointer field is record-SHAPED and `OnHit := nil` has to keep the
zero-fill arm (`bug-a-assigning-nil-to-a-method-pointer-segfaults`) — widening
the whole-array predicate is exactly the change that could steal it, so it is
asserted here rather than left to the ticket that owns it.

## Log
- 2026-09-06 — fixed and resolved; see the commit carrying this file.
