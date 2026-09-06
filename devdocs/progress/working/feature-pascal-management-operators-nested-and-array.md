---
slug: feature-pascal-management-operators-nested-and-array
title: "Management operators do not reach an array element or a nested field"
track: P
prio: 35
type: feature
status: working
owner: frankA
blocked-by: []
summary: "PARTLY DONE 2026-09-06 (frankA): a managed record reached through a FIELD at any depth, and through an ELEMENT of a FIXED one-dimensional array, are both initialized and finalized now -- local and global. STILL REFUSED, each with its own fixture naming why: a DYNAMIC array (its extent is a runtime length the desugar cannot read), a MULTI-DIMENSIONAL one (the synthesised loop is 1-D), a record holding a managed record behind an ARRAY field, and a CLASS field. THE CLASS CASE IS NOT THIS DESUGAR'''S JOB and the ticket said it was: measured, fpc runs a class field'''s Initialize inside Create and its Finalize inside Free, so a scope-bound try/finally would finalize a live heap object at every scope exit and never run for one that outlives the scope -- it belongs on the constructor and destructor paths. THE ORDER IS NOT UNIFORM AND THIS TICKET HAD ONE OF THE TWO RULES WRONG: across NESTING levels Initialize is POST-order and Finalize is PRE-order, but ACROSS ARRAY ELEMENTS both run ASCENDING -- fpc does not reverse an array on the way out. The Symptom section above claimed `fin 3 / fin 0`, i.e. descending, and that is refuted by fpc 3.2.2'''s own output in test_mgmt_operators_array.expected. THE GLOBAL ARRAY DIVERGES FROM FPC IN BOTH DIRECTIONS AND DELIBERATELY: measured, fpc runs NOTHING for a global array (`body 000`) while it does run Initialize for a plain global record, so its omission is about the array and leaves a declared invariant that never runs; we initialize, and we finalize, the latter being the already-chosen position for the non-array case. CORPUS: tmoperator7 advanced from line 101 to line 117 and still stops on this ticket -- its array is DYNAMIC (SetLength), so the fixed-array arm that landed cannot clear that row. tmoperator4'''s TA/TB are CLASSES, so it is the class row, and the record nested-field arm had no corpus row at all. Refused rather than skipped, by design -- a declared invariant that simply never runs is a plausible wrong value far from the cause."
---

# Management operators do not reach an array element or a nested field

- **Type:** feature (Pascal frontend, operator overloading)
- **Track:** P (shared `parser.inc` — A-gated)
- **Status:** working
- **Follows:** [[feature-pascal-class-management-operators]] — slice 3 refuses
  these shapes rather than compiling them silently.

## Symptom

    error: an array of a record with a management operator is not supported yet
    error: a field of a record with a management operator is not managed yet

`class operator Initialize/Finalize` fires for a variable **of** the managed
record type. It does not fire for:

- `arr: array[0..1] of TFoo` — FPC initializes and finalizes every element;
- `b: TBar` where `TBar` has a `TFoo` field, at any depth;
- a class whose field is a managed record (same check, `tyClass` arm).

Measured against FPC 3.2.2, which does all three:

    var b: TBar;              ->  init / ... / fin 7
    var arr: array[0..1] ...  ->  init 0 / init 1 / ... / fin 0 / fin 1

The second row read `fin 3 / fin 0` until 2026-09-06 — descending, which is
what a scope-exit rule looks like if you assume arrays unwind the way locals
appear to. **fpc does not reverse array elements.** Corrected against 3.2.2's
own output, which is now `test/test_mgmt_operators_array.expected` byte for
byte. The pre/post-order rule that DOES hold across nesting levels is a
different rule and still applies within each element.

## Why it is refused rather than skipped

A record whose declared invariant simply never runs is worse than a program
that does not compile — the failure would be a plausible wrong value far from
the cause, which is the expensive shape in this repo. So the scan errors and
names this ticket.

## Root cause

`WrapManagementOpsRange` (`compiler/parser.inc`) is a **per-symbol** desugar:
for each managed local/global it emits `Initialize(v)` and a `try..finally
Finalize(v)`. FPC gets the recursion free because it drives the whole thing off
the type's RTTI. Reaching an element needs a synthesised loop; reaching a field
needs a synthesised field path.

## Sketch

Generalise the emitter from "a symbol" to "an lvalue node + its type":

- record field -> a field-access node, recursing on the field's recId;
- static array -> a synthesised `for i := lo to hi do Op(base[i])`, which the
  AST can already express;
- dynamic array / class instance field -> a runtime walk, i.e. genuinely the
  RTTI shape FPC uses; probably out of scope for the desugar and the point at
  which a Track A ticket for record RTTI descriptors is the right answer.

Do the two static cases first — they are what the conformance tests use — and
keep the refusal for the rest.

## Gate

`make compiler/pascal26` (self-host fixedpoint) + the repro programs diffed
against FPC 3.2.2 + `tools/gate.sh quick`. The refusal fixtures under `test/`
must be converted from "refused" to "matches FPC" as each case lands.

## 2026-09-06 (frankS) — the two corpus rows, one per arm

Measured at `88a0b3d93835`:

| row | line | arm |
| --- | --- | --- |
| `tmoperator4.pp` | 81 | `a field of a record with a management operator is not managed yet` |
| `tmoperator7.pp` | 101 | `an array of a record with a management operator is not supported yet` |

One row per arm, which is the argument for keeping both arms in one ticket: a
fix that lands only the field path leaves a live corpus row on the other
refusal, and the two share `WrapManagementOpsRange`.

**tmoperator7 did not reach line 101 until today.** It stopped at line 29 on
`undefined variable (InitializeCount)` — a `class var` of the record, named
unqualified from inside `class operator TFoo.Initialize`, which pxx parsed as a
bare global function with no record scope. That was a NAME-RESOLUTION defect
with nothing to do with management operators, and the row's skip reason recorded
it as *"the management-operator cluster"* because that is what the file is about.
Fixed in the same commit as this note. **A row's skip reason is a claim about
where it stops, and where it stops is a claim about one line — everything past
it is unverified.**

## What is NOT in this ticket

`System.InitializeArray` / `FinalizeArray` — the RTTI-driven form
(`InitializeArray(P, TypeInfo(TFoo), N)`) that tmoperator2/3/9 use. This
ticket's own Sketch predicted it: *"dynamic array / class instance field -> a
runtime walk, i.e. genuinely the RTTI shape FPC uses; probably out of scope for
the desugar and the point at which a Track A ticket for record RTTI descriptors
is the right answer."* That ticket now exists and has three corpus rows:
[[feature-a-record-rtti-descriptors-for-initializearray-and-finalizearray]].

## 2026-09-06 (frankA) — the record NESTED-FIELD arm lands, and the class arm is a different mechanism

**Done: a record that CONTAINS a managed record, at any depth.** The desugar
walks the field table and builds a field path per call (`AN_FIELD` over a cloned
base), so `b: TBar` with `TBar.f: TFoo` now initializes and finalizes exactly as
fpc does. Two levels deep works, and so does a record with BOTH its own operator
and a managed field.

**THE ORDER IS NOT UNIFORM AND I WOULD HAVE GUESSED IT WRONG.** Measured against
fpc 3.2.2 before writing any of it:

| | order |
| --- | --- |
| `Initialize` across nesting | **POST**-order — the fields, then the record's own operator |
| `Finalize` across nesting | **PRE**-order — the record's own operator, then the fields |
| both, within one level | declaration order **FORWARD** |

The two halves look contradictory side by side and are both real: construct /
destruct symmetry ACROSS levels, and no reversal at all among siblings, array
elements or the locals of a scope. `a`, `n.p`, `n.q`, `b` finalize 0,1,2,3 — fpc
does not reverse them. A test asserting only "Initialize and Finalize both ran"
passes with either rule inverted, so every row in the new fixture prints a
distinguishable number.

**THE CLASS ARM IS NOT "the same check, tyClass arm" — it is a different
LIFETIME and therefore a different insertion point.** Measured: for `c: TCls`
whose field is a managed record, fpc runs the field's `Initialize` inside
`TCls.Create` and its `Finalize` inside `Free`. Nothing happens at scope entry
or exit. A scope-bound `try/finally` — which is all this pass can emit — would
finalize a LIVE heap object at every scope exit and would never run for an
object that outlives the scope. Wrong in both directions, so it stays refused
and it does not belong in this desugar at all; it belongs on the constructor and
destructor paths.

**AND THE CORPUS EVIDENCE WAS ATTRIBUTED TO THE WRONG ARM.** This ticket's
summary cites *"tmoperator4 (line 81, the nested-field arm)"*. tmoperator4's
`TA` and `TB` are **classes** — it is the class-field shape, not the record one.
So the demand sits on the arm that is still refused, and the record nested-field
arm that just landed had **no corpus row at all**. That is not an argument
against having done it: fpc does it, the refusal was reachable from ordinary
source, and it is the smaller half of what was one ticket. It is an argument for
not reading the corpus citation as covering both arms, which is exactly what
"one row for each arm" invited.

**Still refused, and each now has its own fixture naming why:** an array of a
managed record (the symbol case), an ARRAY FIELD inside a record at any depth
(same missing loop — and `UFldTk` carries the ELEMENT kind, so a guard reading
only the kind lets it through silently; `UFldIsArray` is what separates them),
and the class case above.

**The old `test_mgmt_operators_field_refused` fixture EXPIRED and was re-aimed
rather than deleted.** It asserted that a plain `f: TFoo` field is refused, which
is now false. A fixture that asserts a NEGATIVE turns red the day someone
implements the thing, and it is the one kind of test whose failure means
"succeeded". Re-pointed at the array-field shape; a new
`test_mgmt_operators_class_field_refused` covers the class one, with the
Create/Free measurement in its header so the next reader does not fold it back
in.

## 2026-09-06 (frankA) — the FIXED-ARRAY arm lands, and what it is refuted by

**Done: `arr: array[lo..hi] of TFoo` initializes and finalizes every element**,
as a proc local and as a program global, matching fpc 3.2.2 byte for byte for
the local case (`test_mgmt_operators_array`).

`AppendManagedArrayOps` synthesises `k := lo; while k <= hi do begin <element
ops>; k := k + 1 end`. The element ops are **the same `AppendManagedFieldOps`
walk a plain record local gets**, over an `AN_INDEX` base instead of an
identifier — so an array of records that themselves hold managed fields works
without a second mechanism, and the nesting order rule keeps applying inside
each element.

### The order, measured before it was written

fpc 3.2.2, `b: array[0..1] of TBar` where `TBar` has both its own operators and
a `TFoo` field:

    init Foo 3 / init Bar 4 / init Foo 5 / init Bar 6
    fin  Bar 4 / fin  Foo 3 / fin  Bar 6 / fin  Foo 5

Two rules, and they are not the same rule:

- **across ARRAY ELEMENTS: ascending, both directions.** `b[0]` finalizes before
  `b[1]`. Nothing is reversed on the way out.
- **within one element: post-order in, pre-order out** — the nesting rule this
  ticket already had, unchanged.

The ticket's own Symptom section predicted descending and has been corrected
in place. A test asserting only that both elements ran would have passed either
way, which is why every row prints a distinguishable number.

### Two things the fixture is aimed at that a smaller one would miss

**SOURCE index space.** `test_mgmt_operators_array` declares `array[3..5]`, not
`array[0..2]`. The loop builds an `AN_INDEX` node read exactly the way `a[3]` in
the source is, so it must run 3..5. A loop hard-coded to `0..n-1` is correct for
every 0-based declaration — which is every array anyone writes by reflex — and
silently initializes three slots that are not the array's for the other one.
The bounds come off the symbol: `ConstVal` is the LOW bound (AllocArray stores
it there) and `ArrLen` the extent.

**The refusal and the emission are one predicate.** `SymIsLoopableManagedArray`
is spelled once and both read it. A shape the refusal lets through and the
emission skips is a declared Initialize that silently never runs — which is the
exact defect `regression-test-core-test-mgmt-operators` was written for, and it
arrived last time through two conditions that were *supposed* to agree.

### The global array diverges from fpc, in the direction of running more

Measured on the fixture itself: fpc 3.2.2 prints `body 000` and no operator line
at all for a global array, while for a plain global *record* it runs Initialize.
So the omission is about the array, not about globals. `_global_array.expected`
is therefore ours rather than fpc's, and the header carries both divergences —
the second (no Finalize for a record global) being the position already chosen
in `test_mgmt_operators`'s header, which this inherits.

### Still refused, each with its own fixture

`array_refused` is now the DYNAMIC case and `multidim_array_refused` the 2-D
one: two clauses of one predicate, so neither row can stand in for the other —
a 2-D array has a fixed `ArrLen` and would sail past a dynamic-only check. Both
fixtures were re-aimed rather than deleted, because a test whose whole claim is
"we do not support X" goes red the day someone implements X.

### The corpus row does not clear, and that is the honest reading

`tmoperator7` moved from line 101 to **line 117** and still stops on this
ticket's refusal — its array is `SetLength(FoosObj, ...)`, i.e. DYNAMIC. The
fixed-array arm cannot clear it. Advancing 16 lines is real progress through the
file and it is not a closed row; whoever takes the dynamic case owns that one.
