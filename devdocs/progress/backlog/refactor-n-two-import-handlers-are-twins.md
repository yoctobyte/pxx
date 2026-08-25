---
track: N
prio: 45
type: refactor
blocked-by: []
summary: "PyParseOneImport (105 lines, 1 caller) and PyParseImportRun (283 lines, 4 callers) are two handlers for one concept — the tree already calls them 'the twin list' and 'the twin site'. The duplication is not cosmetic: it is why a relative import fails with two DIFFERENT errors depending on which one it reaches, and why fixing it has an ordering constraint at all."
---

# Two `from ... import` handlers are twins

- **Type:** refactor — **Track N** (`compiler/pyparser.inc`; both handlers are
  N's file, no Track A handoff).
- **Split out of** [[bug-n-relative-import-from-a-package-is-not-parsed]] after
  a bounded check asked for by the coordinator: the merge is right but is a
  parser refactor, not something to do inside a ticket about compiling
  webencodings.

## The duplication, measured

| | `PyParseOneImport` (:31583) | `PyParseImportRun` (:31688) |
| --- | --- | --- |
| size | 105 lines | **283 lines** |
| callers | **1** — :23635, an import inside a block | **4** — :17820, :32012, :32778, `PyPreScanImports` |
| forward decl says | "ONE import statement, inside a block" | "`import` / `from ... import`, **wherever it appears**" |

`PyParseImportRun` is a **superset**, not a peer. Its extra ~178 lines are alias
binding (`PyImpAliasSym`), consumed-only roots (itertools / collections), the
`typing` special list, and soft/try-import handling.

**The tree already knows.** `:31581` — *"Shares the resolver with
PyParseImportRun"*. `:31890` — *"see the **twin list** in PyParseOneImport"*.
`:31900` — *"the **twin site** in PyParseOneImport"*. Three comments naming the
duplication and none removing it.

## Why it is worth fixing rather than living with

This is not tidiness. The duplication has a measured, user-visible cost:

- A relative import produces **two different errors depending on which handler
  it reaches** — `undefined variable (from)` via one, `undefined variable (sub)`
  via the other. Same source, same defect, different diagnosis.
- Fixing relative imports **has an ordering constraint only because of this**:
  widening `PyPreScanImports` to accept a leading dot reroutes `from . import x`
  from the handler that copes to the one that does not, so the runner must learn
  the relative forms *first*. An ordering constraint between two handlers is a
  symptom of the duplication, not a fact about imports.
- Every future import feature has to be written twice or silently works in one
  position and not the other — which is exactly how this bug arose.

`devdocs/dev/normalise-dont-special-case.md`: the second path is the one that
stays broken. `devdocs/dev/root-cause-over-microfix.md`: measure by
tickets-closed-per-change, and the overhaul is often smaller because it deletes
cases.

## Shape

`PyParseImportRun` becomes a loop whose body is `PyParseOneImport`, after
lifting the superset's ~178 lines into the shared body. The work is not the
merge itself but re-verifying the four call paths — one of which is the prescan,
whose routing is precisely what is fragile here.

## Gate

`make compiler/pascal26` + `tools/gate.sh quick` **before committing** (the FPC
seed canary only runs while `compiler/**` is dirty), plus explicit coverage of
each of the four call positions: a module-level import, an import inside a
block/function, an import inside `try:`/`except ImportError:`, and one reached
through the prescan. Both relative forms (`from . import x`,
`from .mod import x`) run **after every routing change** — see the trap recorded
on the originating ticket.

## 2026-08-17 — this is no longer a tidiness argument; it is a defect generator with a measured rate

Two defects in two days trace to the split, and the second one is the shape that
makes the case:

1. [[bug-n-relative-import-from-a-package-is-not-parsed]] — the routing
   *condition* is duplicated at three sites, and a session that found two of
   them derived a three-step plan from the pair that did not survive contact
   with the third.
2. [[bug-n-from-import-as-alias-binds-zero-inside-a-pulled-module]] — **a fix
   applied to one twin and not the other.** `bug-nilpy-from-import-as-alias-is-
   discarded` was fixed in `PyParseImportRun` alone; `PyParseOneImport` still
   parses `as` and drops it. Silent wrong value: the alias read as 0, no
   diagnostic.

Item 2 is the one to weigh. It is not "the code is duplicated", it is "we
already fixed this bug once and it stayed broken on the other path", which is
precisely `normalise-dont-special-case.md`'s failure mode — the second path is
the one that stays broken. The rate is what is new: the twins were known and
labelled in-tree ("the twin list", "the twin site") and that labelling did not
prevent either defect.

Not taken yet — the corpus rungs come first — but the cost side of this ticket's
trade-off should now be read as ongoing, not one-off.
