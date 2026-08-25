---
slug: bug-p-a-pointer-to-a-pointer-to-a-record-cannot-be-dereferenced-twice
title: "`pp^^.field` over a `^PRec` is refused, and the Delphi-mode single-`^` spelling resolves no record at all"
track: P
prio: 40
type: bug
blocked-by: []
status: backlog_new
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
