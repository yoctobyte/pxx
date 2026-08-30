---
track: A
prio: 45
type: refactor
blocked-by: [bug-a-a-nested-routine-cannot-capture-a-fixed-size-array]
summary: "ParseSubroutine registers a routine's params on THREE paths — `external` (which then Exits), forward/interface, and the body pass — and each hand-copies the ~20 durable ProcParam* columns. Measured 2026-08-30 BEFORE they were equalised: body wrote all of them, forward 14, external THREE, and that one asymmetry produced three divergences from fpc in both directions. All three copies are now complete, so no defect is open; the DUPLICATION is, and it is a standing trap because a new column added to one copy silently misses the other two. The collapse is written and blocked: the 21 staging arrays are fixed-size locals the compiler cannot capture in a nested routine, and ParseSubroutine is re-entrant so they cannot be globals."
status: new
owner: ""
---

# The durable param row is hand-copied on three registration paths

- **Type:** refactor — **Track A** (`compiler/pasparser_proc.inc`).
- **Filed:** 2026-08-30 (frankS), resolving
  [[bug-a-an-external-routines-pointer-param-pointee-is-never-recorded-so-a-class-argument-is-accepted]].
  That ticket's own diagnosis proposed this collapse; this records why it did
  not land with the fix, so the next holder does not rediscover the blocker.

## What is already done

All three copies now write the full row, and the canonical explanation lives at
the body path's copy (search `THE DURABLE PARAM ROW`). **No behavioural defect is
open.** Three regressions guard it (`test_param_row_external_forward_fail.pas`,
`..._ok.pas`), both non-vacuous against `pinned`.

## What is not

Three copies of one concept, which is precisely the shape
`normalise-dont-special-case.md` names: **the second and third are the ones that
stay broken.** The evidence is that they already did — the divergence was
*silent for as long as the file has had three paths*, and it took reading the
pointer family side by side to see it. A new `ProcParam*` column will be added
to one copy and not the others, and the failure will again be a value that is
merely *absent* rather than wrong, which is why it fails open.

## The blocker, measured not assumed

The natural form is a nested `PersistParamRow(procIdx, i)` inside
`ParseSubroutine`, called from all three. It was written and does not compile:

```
pascal26:597: error: nested routine: capture of fixed-size array 'pconst' not yet supported
```

The ~21 staging arrays (`ptypes`, `ptypesRec`, `pconst`, `pdefault*`,
`pDynDepth`, `pElemRow*`, …) are fixed-size locals.
[[bug-a-a-nested-routine-cannot-capture-a-fixed-size-array]] is the blocker.

**And they cannot simply become globals:** `ParseSubroutine` is **re-entrant** —
`pasparser_call.inc:272` calls it from an anonymous-method body, so a global
staging set would be clobbered by an inner routine parsed inside an outer one's
parameter-to-persist window. Checked, not assumed.

**Rejected alternative, recorded so it is not re-proposed:** a top-level
procedure taking the arrays as `var` params of named array types. 23 parameters,
15 of them the same `array of Integer` type — a transposed pair **type-checks**.
That trades a silent missing column for a silent wrong one, which is worse.

## Fix, once unblocked

Land the nested `PersistParamRow`; replace all three copies with a call; keep
the canonical note on the procedure. Adding a column then reaches every path by
construction, which is the property the three copies cannot have.

## Gate

`make compiler/pascal26` + both `test_param_row_external_forward_*` tests
unchanged + a fourth row added to one of them exercising a column, to prove the
single write site actually reaches all three registration paths.
