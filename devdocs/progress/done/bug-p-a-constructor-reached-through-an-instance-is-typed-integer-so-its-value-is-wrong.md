---
track: P
prio: 40
type: bug
blocked-by: []
status: done
owner: frankS
---

# A constructor reached through an INSTANCE is typed Integer, so its value is wrong

`R.Create(...)` on an existing variable — FPC re-runs the constructor on that
instance and the expression's VALUE is the instance. pxx built the call
correctly and then typed the result from `Procs[mpi].RetType`, which for a
constructor is `tyInteger`: `ParseRecordMethodDecl` sets `isFunc := False` for
`isCtor`, so no return type is ever recorded. The metaclass and type-name arms
both override this by hand (`outTk := tyClass; outRec := REC_UCLASS_BASE + ci`);
the INSTANCE arm did not.

**Both arms were broken identically** — `class` behaved exactly as `record`,
which is unusual here: the record/class split is normally where one arm was
fixed and the sibling was not. Neither was, which is what pointed at the shared
instance-method path rather than at either type's own.

MEASURED 2026-09-07 against fpc 3.2.2. Four spellings, four different
behaviours, and it took **three** changes in three files to close them:

| spelling | before | after |
| --- | --- | --- |
| `R.Create(False);` statement | `10 20` correct | `10 20` |
| `R2 := R.Create(False);` | **`20 20`**, and `0 0` for the class arm | `10 20` |
| `Show(R.Create(False))` | `no overload of Show ... (Integer)` | `10 20` |
| `Writeln(R.Create(False).X)` | `IR_UNSUPPORTED` (kind 8) | `10` |

1. **`pasparser_lval.inc`** — the instance-method arm builds `(call, receiver)`
   as an `AN_COMMA` and types it from the receiver. The receiver is a FRESH
   `AN_IDENT`, not the original node, which is already hanging off `mselfArg`;
   putting one node in the tree twice would evaluate the receiver twice.
   Restricted to an `AN_IDENT` receiver for that reason, which is also the only
   shape FPC accepts here.
2. **`pasparser_stmt.inc`** — the statement spelling then regressed to
   `expected ':=' before ';'`, because a comma in lvalue position is not a
   statement kind. That door's own comment predicted this: *"it enumerates the
   node kinds a desugaring may hand back in lvalue position, and it has no
   diagnostic when a new one is missing"*. Narrow on purpose — a bare `AN_COMMA`
   is NOT safe to widen to, since the dyn-array materialisations build one too
   and theirs CAN be an assignment target; only the ctor desugaring puts a CALL
   on the left.
3. **`ir.inc`** — `IRLowerAddress` keeps an allow-list of kinds whose ADDRESS it
   can produce and `AN_COMMA` was not on it, so the selector form still refused.
   That routine's own comment records the same split for kinds 53, 58 and 88:
   `r := f(x)` fine, `f(x).c` refused. Fourth instance. The arm invents no
   address — it recurses — so an operand that has none still refuses, which is
   what keeps it from turning a refusal into the segfault
   `pasparser_lval.inc ~6205` records for exactly this shape.

## Verification

`test/test_instance_reached_constructor_value.pas`, differential against fpc,
ten rows: statement / assignment / argument position for record AND class, one
selector, two selectors deep, and a bare construction statement. Row 1 is the
regression canary — the statement form was the one spelling already working and
change (1) broke it.

Positive control takes TWO runs, because the refusal masks the wrong value.
Against pin v407 (`095ef4811a5b`) the file does not compile at all, refusing in
three different places, one per change; with the argument rows removed the SAME
pinned compiler runs it and prints `assig 20 20` and `assiC 0 0` against fpc's
`10 20` — the class arm answering a zeroed record.

`gate.sh quick` GREEN with the FPC seed canary PASS.
Conformance `411 pass, 0 fail, 89 skip, 50 auto-gated (of 550)`, up from 410/90.

## What it burned

- **`terecs15.pp`** — burned. Line 71 was the whole of what was left of it.
- **`texception10.pp`** — *not* burned, but its statement half is fixed and its
  reason is now accurate. `TMyObject.Create(nil);` with no destination was
  `expected ':=' before ';'` (`AN_METACLASS_NEW` is a construction, not one of
  `ASTNodeIsCall`'s five kinds — the second kind added through that same door
  in one change). It compiles now and SIGSEGVs, because the row's other half is item 3
  of [[decide-segv-runtime-error-default]] (rainy-day): a catchable
  `EAccessViolation` from signal context. Decided territory, not a gap to take.

## Log
- 2026-09-07 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 80e8957ed.
