---
slug: refactor-a-one-predicate-for-a-tyrecord-that-is-a-fat-pointer
title: "Two places answer 'this tyRecord is a fat pointer, not a record', and one of them has drifted"
track: A
prio: 35
type: refactor
blocked-by: []
status: new
owner: ""
created: 2026-08-30
summary: "An interface and a method pointer are both spelled tyRecord and neither is one, so any rule keyed on tyRecord has to stand down for both. symtab.inc:8130-8141 asks the pair together for a PARAMETER. AssignSideKind (ir.inc:87) asks it for an ASSIGNMENT DESTINATION and, until the methodptr-nil fix, carried only the interface half -- which is how `OnClick := nil` became a compile error for a field, an array element and a loop-written element while it kept working for a plain variable. Two copies, one already drifted, before either had a name."
---

# The question

`tyRecord` describes the STORAGE of three unrelated things: a real record, an
interface (a 16-byte `{IMT, instance}` fat pointer) and a method pointer (a
16-byte `{Code, Data}` pair). So every rule that refuses something *because* the
destination is `tyRecord` must first ask "is this actually a record?" — and that
question has two conditions, always the same two.

| site | asks | covers |
| --- | --- | --- |
| `symtab.inc:8130-8141` (`MatchArgNilOk`'s neighbour) | may `nil` bind this **parameter**? | `MethodPtrRecId` **and** `UClsIsInterface` |
| `ir.inc:87` `AssignSideKind`, `AN_IDENT` arm | may this **destination** be kind-checked? | procvar via `SymProcSig`, **and** `UClsIsInterface` |
| `ir.inc:87` `AssignSideKind`, `AN_INDEX/AN_FIELD/AN_DEREF` arms | same | interface only — **the drift** |

The third row is the defect, filed and fixed as the method-pointer half of
`bug-p-methodptr-nil-assign`: the three arms added by `fa8f2424d` inherited one
of the two conditions, so `c.OnHit := nil` and `arr[1] := nil` were refused with
`cannot assign Pointer to record` while `ev := nil` kept working.

**That fix is a one-line bail and it is the right fix.** This ticket is the
observation underneath it: the pair had **no name**, so a new call site had to
re-derive it, and re-derived half.

# Shape

One predicate — `RecIsFatPointer(rec: Integer): Boolean`, `MethodPtrRecId` or
`UClsIsInterface`, both with the `REC_NONE` and `MAX_UCLASS` guards the existing
copies already carry — called from all three rows. Note the `AN_IDENT` row asks
its half a *different* way (`SymProcSig >= 0`, which bails on **any** procvar,
not just a method pointer); check before collapsing it whether that breadth is
load-bearing there or incidental, because a plain procvar is spelled `tyPointer`
and the record rule cannot fire on it.

**Do not treat "they agree today" as evidence.** Row three agreed with row one
about interfaces and disagreed about method pointers, and the disagreement was a
compile error on ordinary code (`OnClick := nil` is how you detach a handler).
Build the control the way `refactor-a-two-predicates-answer-what-a-caret-yields`
did: a probe per condition per site, run against a binary with the predicate and
one without, so the takeover is positive rather than an absence of complaints.

# Gate

Track A: `make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick`, pinned
by `test/test_methodptr_nil_assign.pas` and the assign fail/ok pair
(`test_assign_lvalue_shapes_fail` / `_ok`, whose 12-row count is itself the
assertion).
