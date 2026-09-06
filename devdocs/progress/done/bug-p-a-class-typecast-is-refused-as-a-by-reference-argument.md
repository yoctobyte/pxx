---
track: P
prio: 40
type: bug
blocked-by: []
status: done
owner: frankD
created: 2026-09-06
summary: "`Bump(TBase(d))` — a variable typecast over an lvalue passed to a `var` parameter — is refused with `by-reference argument must be a variable`, while `BumpPtr(PtrUInt(u))` on the same shape compiles. `IsVarArgLvalueCast` (pasparser_call.inc) listed `AN_PTR_CAST` and nothing else; `IRLowerAddress` has peeled `AN_CLASS_CAST` too since the interface-cast arm went in, so the capability was already present and only the RECOGNISER was short a member. `d as TBase` must stay refused — it yields a value, and fpc 3.2.2 refuses it in this position as well. Live case: fcl-passrc pastree.pp:2101, `ReleaseAndNil(TPasElement(InterfaceName))`, three times in one destructor. FIXED 2026-09-06."
---

# A class typecast is refused as a by-reference argument

- **Type:** bug (compat — everyday Pascal is refused) — **Track P**
  (`compiler/pasparser_call.inc`).
- Found in fcl-passrc rung 7, [[feature-pascal-corpus-passrc]].

## The measurement

```pascal
Bump(TBase(d));        { class hard cast  — refused }
Bump(TBase(o.Fld));    { over a field     — refused }
BumpPtr(PtrUInt(u));   { pointer spelling — COMPILES }
```

fpc 3.2.2 `-Mobjfpc` compiles all three. pxx answered
`error: by-reference argument must be a variable` on the first two.

## Where it was decided

`IsVarArgLvalueCast` accepted `ASTKind[n] = AN_PTR_CAST` only. That is an
**enumerated predicate** — a hand-maintained node-kind list that must grow per
new member, with no diagnostic when it does not. `AN_CLASS_CAST` was the
member it never got. The backend was never the limit: `IRLowerAddress` peels
both kinds.

## What must NOT be added to the list

`d as TBase` performs a checked conversion and produces a **value**. Accepting
it would take a temp's address and drop the callee's write on the floor, with
the call still compiling — a silently wrong program in place of a refusal. fpc
3.2.2 also refuses it here (`Can't take the address of constant expressions`),
so the boundary is not ours to move. Named in the test header so the next
reader does not "complete" the list.

## Resolution 2026-09-06

`IsVarArgLvalueCast` accepts `AN_PTR_CAST` or `AN_CLASS_CAST` over
`AN_IDENT`/`AN_FIELD`/`AN_INDEX`/`AN_DEREF`.
`test/test_a_class_typecast_is_a_by_reference_argument.pas`, wired in the
Makefile, byte-identical to fpc:

```
var    : nil
field  : nil
element: nil neighbour: live 9
ptrcast: 42
```

**Every row asserts the callee's `nil` ARRIVED, not that the call compiled** —
a fix that materialised a temp would compile every row and change no output
except this file's. `Arr[0]` is created deliberately: an un-created slot is
`nil` too, and `nil` is what a *correct* `Bump` writes, so the neighbour column
would have been a control whose expected value collided with its failure value.

## Log
- 2026-09-06 — fixed and resolved; see the commit carrying this file.
