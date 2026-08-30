---
slug: refactor-a-one-predicate-for-a-tyrecord-that-is-a-fat-pointer
title: "Two places answer 'this tyRecord is a fat pointer, not a record', and one of them has drifted"
track: A
prio: 35
resolved: d5fd2a6ca
type: refactor
blocked-by: []
status: rejected
owner: ""
created: 2026-08-30
summary: "REJECTED — already done in d5fd2a6ca, forty minutes before this was filed. frankS extracted RecIsReferenceShaped (symtab.inc:8116, methodptr OR interface) and routed ProcParamIsNilable and BOTH AssignSideKind arms through it. Verified by rebuilding at HEAD and running test_methodptr_nil_assign.pas: it compiles and passes. The ticket was filed off a symtab.inc read at the sha in my checkout, without pulling first."
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


---

# Rejected — it had already landed when this was written

**2026-08-30, frankA, the same hour.** `d5fd2a6ca` (frankS) is exactly the shape
this ticket asked for:

- `symtab.inc:8116` — `RecIsReferenceShaped(rec)`, `MethodPtrRecId` **or**
  `UClsIsInterface`, one name for the pair.
- `symtab.inc:8170` — `ProcParamIsNilable` delegates to it.
- `ir.inc:106` and `ir.inc:151` — **both** `AssignSideKind` arms call it, so the
  drift this ticket was about is gone rather than documented.

Measured rather than read off the diff: rebuilt at HEAD (fixedpoint, 2 rounds)
and ran `test/test_methodptr_nil_assign.pas` — compiles, and all three cleared
shapes report `assigned=FALSE` after being armed and called.

## Why it was filed anyway, which is the part worth keeping

I read `symtab.inc:8130-8141` **at the sha in my checkout** and wrote the ticket
from it. The predicate had existed for forty minutes. `git fetch`/`pull` before
*filing* — not merely before *writing* — is the cheap fix, and it is the same
error the coordinator made tonight from the other side: an absence read as a
fact about the repo when it was a fact about one working tree.

**A ticket asserts a present-tense claim about the codebase.** That makes filing
one a measurement, subject to the same staleness rule as any other, and the
board is where a stale claim is most expensive: nobody re-derives it, they act
on it. This one would have sent its resolver to write a predicate that was
already three call sites deep.
