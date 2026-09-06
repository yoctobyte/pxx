---
slug: feature-pascal-management-operators-nested-and-array
title: "Management operators do not reach an array element or a nested field"
track: P
prio: 35
type: feature
status: backlog
owner: ""
blocked-by: []
summary: "`class operator Initialize/Finalize` fires for a variable OF the managed record type and not for an ELEMENT of an array of it, nor for a FIELD of a record or class that contains one at any depth. Refused rather than skipped, by design -- a declared invariant that simply never runs is a plausible wrong value far from the cause. fpc 3.2.2 does all three. The fix generalises WrapManagementOpsRange from per-SYMBOL to per-LVALUE-node: a field path for the nested case, a synthesised `for i := lo to hi` for the static array; the DYNAMIC array and class-instance-field cases are the RTTI walk fpc uses and belong to [[feature-a-record-rtti-descriptors-for-initializearray-and-finalizearray]]. CORPUS EVIDENCE, measured 2026-09-06 at 88a0b3d93835: fpc testsuite tmoperator4 (line 81, the nested-field arm) and tmoperator7 (line 101, the array arm) stop on this ticket's own two refusal strings -- two of the six live tmoperator rows, one for each arm, which is why both arms are in one ticket. tmoperator7 only reaches line 101 since the class-operator scope fix landed the same day; before it, the row stopped at line 29 on `undefined variable (InitializeCount)` and was skipped as a management-operator row for a defect that was nothing of the kind."
---

# Management operators do not reach an array element or a nested field

- **Type:** feature (Pascal frontend, operator overloading)
- **Track:** P (shared `parser.inc` — A-gated)
- **Status:** backlog
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
