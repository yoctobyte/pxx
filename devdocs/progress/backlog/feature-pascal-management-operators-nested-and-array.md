---
prio: 40
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
