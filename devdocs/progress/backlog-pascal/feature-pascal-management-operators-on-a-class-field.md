---
slug: feature-pascal-management-operators-on-a-class-field
title: "A class field of a managed record type is never initialized or finalized"
track: P
prio: 30
type: feature
status: open
owner: ""
blocked-by: []
summary: "DESIGNED 2026-09-09 (frankS), NOT implemented -- the design section carries the fpc oracle, the two insertion points, and the one hazard that makes the obvious implementation a DEADLOCK rather than a wrong value: the Finalize half must NOT go in PXXRecordRelease (`nothing here runs user code` is what lets it be called with the heap lock held; a management operator is user code and may allocate -- this is what cb2ed843 was reverted for) but one function up, in PXXClassFinalize's already-unlocked kind-4 pass. Initialize needs a NEW BUILTIN because TDer declaring no constructor has no body to wrap and AN_METACLASS_NEW knows its class only at runtime. Descriptor: a new member KIND (8 is free) is bootstrap-safe by defs.inc's own note where a header field is not, and bytes +8..+15 of a 16-byte member are unread by kinds 1-7. ORIGINAL: `c: TCls` where TCls has a field of a record with `class operator Initialize/Finalize`: pxx REFUSES it, naming feature-pascal-management-operators-nested-and-array. It was carved out of that ticket 2026-09-06 because it is a DIFFERENT MECHANISM, not a remaining case of the same one. Measured against fpc 3.2.2: a class field's Initialize runs inside Create and its Finalize inside Free -- an OBJECT lifetime, not a scope one. The desugar that serves records is `Initialize(v); try BODY finally Finalize(v)` around the declaring routine's body, and applying it here would finalize a live heap object at every scope exit and never run at all for one that outlives the scope, which is worse than the refusal. The insertion points are the constructor and destructor paths, so the shape is closer to how a class's ARC/interface fields are already handled than to anything in the record desugar. CORPUS: fpc testsuite tmoperator4 stops at line 81 on this refusal, and its TA/TB are CLASSES -- that row was mis-attributed to the record nested-field arm, which had no corpus row at all."
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

## Design, measured (2026-09-09, frankS) — implementable, and NOT implemented

Claimed, worked the design, released without code. Everything below is measured
at binary `68421d8ff193`; the reason it is not built is the lock hazard in §3,
which turns the obvious implementation into the deadlock a previous commit was
reverted for.

### 1. The oracle, exactly

`fpc 3.2.2 -Mobjfpc`, one program, a class with a managed field, a DESCENDANT
adding a second one, an object freed in scope and one that outlives it:

```
  TFoo.Initialize          <- BEFORE the constructor body
  TCls.Create tag=1 f.v=5  <- the ctor already sees the initialised field
  TCls.Destroy tag=1       <- the destructor body runs FIRST
  TFoo.Finalize v=5        <- then the field
```
and for the descendant, **two** `Initialize` before the (inherited) ctor body and
**two** `Finalize` after the dtor body. The object never freed is **never
finalized** — no leak diagnostic, no scope hook.

So: once per managed field of the RUNTIME class, including inherited ones,
before any constructor body and after every destructor body.

### 2. Why it cannot be emitted at compile time

The tempting shape is "wrap each class's own ctor/dtor with its own fields, and
let `inherited` chain them". It does not work: **`TDer` above declares no
constructor at all**, so there is no body to wrap, and it inherits `TCls.Create`,
which would only ever reach `TCls`'s fields. `AN_METACLASS_NEW` makes the same
point from the other side — it allocates the class a classref points at, known
only at runtime.

That is why FPC does this in `InitInstance`/`FreeInstance` off RTTI, and it means
the Initialize half needs **a new builtin** (`PXXClassInitialize(inst)`), called
after the `IR_VMTADDR` stamp at both construction sites (ir.inc's
`-Ord(tkGetMem)` class arm and `AN_METACLASS_NEW`).

### 3. THE HAZARD, and it is the reason this is unstarted

The obvious home for the Finalize half is a new class-descriptor member kind
handled in `PXXRecordRelease`, which is what `PXXClassFinalizeManaged` already
walks. **It is the wrong home and the failure is a deadlock, not a wrong value.**
That function's own header states the invariant it depends on:

> *"Nothing here runs user code: the whole subtree is PXXStrDecRef,
> PXXDynArrayRelease, PXXRecordRelease, PXXVarClear and PXXObjRelease... That is
> what makes it safe to call with the heap lock ALREADY HELD."*

A management operator IS user code and may allocate. Putting it there re-creates
exactly what `cb2ed843` was reverted for.

**The correct home is one function up.** `PXXClassFinalize` already has an
unlocked pass — the kind-4 (COM interface) loop, unlocked *precisely because it
runs the referenced object's destructor chain*. A managed-record field's
`Finalize` belongs in that same pass, and it lands after the user `Destroy`
chain and before `FreeMem`, which is fpc's timing measured in §1.

### 4. Descriptor shape, and why it is bootstrap-safe

`defs.inc` states it in its own words: **a NEW MEMBER KIND has no bootstrap
window** — `ArrCount = 0` makes the entry inert in all six walks, every one a
`while j < arrayCount` over a `case kind of` with no else arm, so an old runtime
walking a new blob does nothing and a new runtime walking an old blob never sees
one. A HEADER change does have that window. So: **new kind, never a new header
field.**

Kinds 1-7 are taken in the class descriptor (7 = promo slot); **8 is free**. A
member is 16 bytes — `{offset:4, kind:4, ?:4, typeRef:4}` — and kinds 1-7 read
nothing at `+8..+15`, which is **8 contiguous bytes: exactly one relocated code
pointer**, or a pointer to a two-entry `{Initialize, Finalize}` table.

### 5. What is left to check before writing any of it

- Whether `rtti_emit.inc` can already emit a RELOCATED pointer into a descriptor
  member (it emits pointers elsewhere in the blob; I did not confirm the helper).
- The ORDER of multiple fields, base-class-first, against fpc — §1 shows two
  calls but a one-field-per-class program cannot separate the orders.
- `RecordManagedFieldCount` and `RecordDescMember` must admit a field whose
  record type has management ops but **no** other managed field, or the record
  is described and never walked. That split is documented in
  `RecordDescMember`'s own header and is the thing that made
  `record v: Variant; end` stay broken.

### 6. Then, and only then

Lift the refusal in `pasparser_proc.inc` (the `tyClass` arm, ~line 851) and
re-aim `test/test_mgmt_operators_class_field_refused.pas` into an output test.
`tmoperator4.pp` (conformance) stops at line 81 on this refusal and is the
acceptance row.
