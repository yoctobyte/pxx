---
slug: feature-pascal-management-operators-nested-and-array
title: "Management operators do not reach an array element or a nested field"
track: P
prio: 35
type: feature
status: working
owner: frankA
blocked-by: []
summary: "PARTLY DONE 2026-09-06 (frankA): a FIELD of a RECORD that contains a managed record now works at any depth, matching fpc including the order, which is not uniform -- Initialize is POST-order across nesting levels, Finalize is PRE-order, and both go forward in declaration order within a level. STILL REFUSED: an ELEMENT of an array of a managed record, an ARRAY FIELD inside a record, and a CLASS field. THE CLASS CASE IS NOT THIS DESUGAR'S JOB and the ticket said it was: measured, fpc runs a class field's Initialize inside Create and its Finalize inside Free, so a scope-bound try/finally would finalize a live heap object at every scope exit and never run for one that outlives the scope -- it belongs on the constructor and destructor paths. THE CORPUS CITATION BELOW IS ALSO MIS-AIMED: tmoperator4's TA/TB are CLASSES, so it is the class row, and the record nested-field arm that just landed had no corpus row at all. Refused rather than skipped, by design -- a declared invariant that simply never runs is a plausible wrong value far from the cause. fpc 3.2.2 does all three. The fix generalises WrapManagementOpsRange from per-SYMBOL to per-LVALUE-node: a field path for the nested case, a synthesised `for i := lo to hi` for the static array; the DYNAMIC array and class-instance-field cases are the RTTI walk fpc uses and belong to [[feature-a-record-rtti-descriptors-for-initializearray-and-finalizearray]]. CORPUS EVIDENCE, measured 2026-09-06 at 88a0b3d93835: fpc testsuite tmoperator4 (line 81, the nested-field arm) and tmoperator7 (line 101, the array arm) stop on this ticket's own two refusal strings -- two of the six live tmoperator rows, one for each arm, which is why both arms are in one ticket. tmoperator7 only reaches line 101 since the class-operator scope fix landed the same day; before it, the row stopped at line 29 on `undefined variable (InitializeCount)` and was skipped as a management-operator row for a defect that was nothing of the kind."
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
    var arr: array[0..1] ...  ->  init / init / ... / fin 3 / fin 0

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
