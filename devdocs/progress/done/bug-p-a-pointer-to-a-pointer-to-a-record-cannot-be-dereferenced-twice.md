---
slug: bug-p-a-pointer-to-a-pointer-to-a-record-cannot-be-dereferenced-twice
title: "`pp^^.field` over a `^PRec` is refused, and the Delphi-mode single-`^` spelling resolves no record at all"
track: P
prio: 40
type: bug
blocked-by: []
status: done
owner: ""
created: 2026-08-25
summary: "With `PPVmt = ^PVmt; PVmt = ^TVmt`, `pp^^.__ClassRef` is refused with `dereferenced value is not a pointer`, and Delphi mode's auto-deref spelling `PPVmt(pp)^.__ClassRef` resolves REC_NONE, so the member becomes a plain AN_FIELD of whatever name follows. Both work in fpc 3.2.2. This is the wall rtl-generics' Generics.Defaults stops at."
---

# Measured, 2026-08-25 (HEAD, `{$mode delphi}`)

```pascal
type
  TFactoryClass = class of TFactory;
  PPVMT = ^PVMT;  PVMT = ^TVMT;
  TVMT = packed record __ClassRef: TFactoryClass; end;
var v: TVMT; p: PVMT; pp: PPVMT; q: TFactoryClass;
begin
  v.__ClassRef := TFactory;  p := @v;  pp := @p;
  q := PVMT(p)^.__ClassRef;     { a }
  q := pp^^.__ClassRef;         { b }
  q := PPVMT(pp)^^.__ClassRef;  { c }
  q := PPVMT(pp)^.__ClassRef;   { d — Delphi auto-deref }
end.
```

| | fpc 3.2.2 | pxx |
| --- | --- | --- |
| a | TRUE | **TRUE** |
| b | TRUE | `dereferenced value is not a pointer` |
| c | TRUE | (not reached) |
| d | TRUE | resolves REC_NONE — see below |

# Two mechanisms, one wall

**`^^` — the honest spelling.** `ResolveDerefShape`'s `AN_DEREF`-over-`AN_DEREF`
arm reads the depth the first `^` parked on the node, but a pointer whose
pointee is itself a NAMED pointer alias arrives with depth 1 rather than 2, so
the second `^` sees a non-pointer. Suspect the same forward-declaration path
that already bites `AliasPtrBaseRec` (below).

**`PPVmt(x)^.field` — the auto-deref spelling.** `ResolveNodeRec`'s `AN_DEREF`
branch has arms for an `AN_IDENT`, `AN_FIELD`, `AN_ADDR` and `AN_INDEX` base and
**none for `AN_PTR_CAST`**, so the record comes back `REC_NONE`, `NodeMetaclassCi`
cannot see that `__ClassRef` is a metaclass receiver, and
`PPVmt(Self)^.__ClassRef.GetHashList(...)` is rejected as `statement is neither a
call nor an assignment`. Same missing-arm family as
`bug-p-length-of-a-dereferenced-pointer-to-array-answers-zero` and
`bug-a-indexing-a-function-call-result-drops-the-field-selector`.

**A partial fix was written and REVERTED, deliberately.** Adding the `AN_PTR_CAST`
arm (element record for a depth-1 alias, the element ALIAS's element for a
depth-2 one, resolved by name because a forward `PPVmt = ^PVmt` records no usable
`AliasPtrBaseRec`) makes the program COMPILE — and then **segfault**, because the
lowering still emits one indirection where two are needed. A clean compile error
traded for a runtime crash is strictly worse, so it was not landed. Whoever takes
this must fix the address computation and the type resolution together, and the
`^^` arm alongside them; the three are one shape.

# Where it was found

Driving `uses generics.defaults` for [[feature-pascal-corpus-generics]]. It is the
wall at `generics.defaults.pas:1865`, reached after two other fixes landed the
same session — `{$DEFINE EXTENDED_HASH_FACTORY := PPExtendedEqualityComparerVMT(Self)^.__ClassRef}`
spliced into ~30 call sites.

# Gate

`make compiler/pascal26` + the four-row repro above diffed against `fpc -Mdelphi
-O1` + `tools/gate.sh quick`. The repro must RUN, not merely compile — that is
the trap this ticket exists to record.

# Resolution 2026-08-25 — fixed, and this ticket's diagnosis was half wrong

Both rows are fixed and the repro above now matches fpc on all four. They were
**two independent defects**, filed and written up separately:

- [[bug-p-a-forward-declared-pointer-to-a-pointer-loses-a-level]] — the `pp^^`
  half. The guess above ("suspect the same forward-declaration path") was right
  in direction and wrong in mechanism: nothing to do with `AliasPtrBaseRec`. The
  forward fixup pass had an arm for a pointer-to-pointer pointee whose guard
  required the element to ALREADY be `tyPointer` — unsatisfiable for a forward
  reference, so the arm could never fire on the case it existed for.
- [[bug-p-a-pointer-to-a-pointer-through-a-typecast-loses-its-depth]] — the
  `PPVmt(x)^` half. **The diagnosis above is wrong.** It blamed a missing
  `AN_PTR_CAST` arm in `ResolveNodeRec`'s `AN_DEREF` branch. That branch is
  fine; it already has that arm. The real cause is that the pointer-alias cast
  in `ParseFactorCore` runs its OWN suffix walk over `^`, built on
  `NodePtrElem`, which knows only the immediate pointee — so the deref nodes
  never got the depth and base that `ResolveNodeRec` reads. Fixing the reader
  was the wrong end, which is exactly why the attempt "compiled and then
  segfaulted": it invented a record identity the address computation did not
  share. Pointing that walk at the shared `ResolveDerefShape` fixed both the
  types and the addresses at once, with no lowering change at all.

The general lesson is the one `devdocs/dev/root-cause-over-microfix.md` states
and this ticket is a clean instance of: **a ticket names a plausible cause, and
9 times out of 10 the real one is deeper.** Here the plausible cause was one
reader missing an arm; the real one was a fourth private copy of the walk that
feeds every reader.

Regression test `test/test_pointer_to_a_pointer_through_a_cast_and_a_forward.pas`
covers all three spellings in both declaration orders.

## Log
- 2026-08-25 — resolved, commit 15ec54d7a.
