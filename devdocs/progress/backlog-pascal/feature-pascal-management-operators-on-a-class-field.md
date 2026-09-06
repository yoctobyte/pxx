---
slug: feature-pascal-management-operators-on-a-class-field
title: "A class field of a managed record type is never initialized or finalized"
track: P
prio: 30
type: feature
status: open
owner: ""
blocked-by: []
summary: "`c: TCls` where TCls has a field of a record with `class operator Initialize/Finalize`: pxx REFUSES it, naming feature-pascal-management-operators-nested-and-array. It was carved out of that ticket 2026-09-06 because it is a DIFFERENT MECHANISM, not a remaining case of the same one. Measured against fpc 3.2.2: a class field's Initialize runs inside Create and its Finalize inside Free -- an OBJECT lifetime, not a scope one. The desugar that serves records is `Initialize(v); try BODY finally Finalize(v)` around the declaring routine's body, and applying it here would finalize a live heap object at every scope exit and never run at all for one that outlives the scope, which is worse than the refusal. The insertion points are the constructor and destructor paths, so the shape is closer to how a class's ARC/interface fields are already handled than to anything in the record desugar. CORPUS: fpc testsuite tmoperator4 stops at line 81 on this refusal, and its TA/TB are CLASSES -- that row was mis-attributed to the record nested-field arm, which had no corpus row at all."
---

# A class field of a managed record type is never initialized or finalized

- **Type:** feature (Pascal frontend, operator overloading)
- **Track:** P (shared `parser.inc` — A-gated)
- **Follows:** [[feature-pascal-management-operators-nested-and-array]] — this
  was the `tyClass` arm of that ticket's refusal until it was measured.

## Symptom

    error: a field of a record with a management operator is not managed yet
           (feature-pascal-management-operators-nested-and-array)

for

    type
      TCls = class
        f: TFoo;   { TFoo has class operator Initialize/Finalize }
      end;

Fixture: `test/test_mgmt_operators_class_field_refused.pas`.

## Why it is not a remaining case of the record ticket

Measured against fpc 3.2.2 before the record arms were written:

| | when it runs |
| --- | --- |
| record field, record variable | scope entry / scope exit |
| record field, CLASS instance | **`Create` / `Free`** |

That is the whole argument. `WrapManagementOpsRange` wraps a ROUTINE BODY, so
everything it emits is scope-bound by construction. A class instance's lifetime
is not, and the two failure modes of pretending otherwise are both silent:

- an object that outlives the scope it was constructed in gets **finalized while
  live**, at that scope's exit;
- an object still referenced at the scope's exit gets finalized **and then used**.

Neither is a case the record desugar can be widened to cover. The insertion
points are the constructor and destructor, which is where the class's own
interface/ARC field handling already lives — that is the code to read first, not
`WrapManagementOpsRange`.

## What is already true

The RECORD side landed 2026-09-06 and is not blocked on this: a managed record
reached through a field at any depth, and through an element of a fixed array,
are both initialized and finalized. The refusal that remains is specifically the
`tyClass` arm, and `RecContainsManagementOp` is the predicate that fires it.

## Corpus

`tmoperator4.pp` stops at line 81 on this refusal. It had been recorded as the
nested-FIELD arm's corpus row; its `TA`/`TB` are **classes**, so it is this
ticket's row. The record nested-field arm that landed had no corpus row at all —
which is worth stating, because "the corpus row for this arm cleared" was
available as a false confirmation and the arm is right on other evidence.

## Gate

`make compiler/pascal26` (self-host fixedpoint) + a trace program diffed against
FPC 3.2.2 covering an object that outlives its constructing scope + one that does
not + `tools/gate.sh quick`. The refusal fixture becomes an output test when this
lands — re-aim it rather than delete it if only part of the shape is covered.
