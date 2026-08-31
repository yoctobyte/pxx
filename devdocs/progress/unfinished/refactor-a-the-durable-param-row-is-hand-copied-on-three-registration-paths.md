---
track: A
prio: 45
type: refactor
blocked-by: [bug-a-a-nested-routine-cannot-capture-a-fixed-size-array]
summary: "WRITTEN AND PARKED 2026-08-31, one step from done: the collapse builds and self-hosts (0a7978a21cbc, 1 round) with both guard tests unchanged, and is committed as a PATCH at devdocs/progress/patches/refactor-a-durable-param-row-collapse.patch. It cannot LAND until a `make pin` — the nested PersistParamRow captures 21 fixed-size staging arrays and `pinned` predates fixed-array capture, so the pinned-seed fixedpoint goes RED and the tree would be unbuildable from the pin for every lane. Needs the pin, not more work. Was: ParseSubroutine registers a routine's params on THREE paths — `external` (which then Exits), forward/interface, and the body pass — and each hand-copies the ~20 durable ProcParam* columns. Measured 2026-08-30 BEFORE they were equalised: body wrote all of them, forward 14, external THREE, and that one asymmetry produced three divergences from fpc in both directions. All three copies are now complete, so no defect is open; the DUPLICATION is, and it is a standing trap because a new column added to one copy silently misses the other two. The collapse is written and blocked: the 21 staging arrays are fixed-size locals the compiler cannot capture in a nested routine, and ParseSubroutine is re-entrant so they cannot be globals."
status: working
owner: frankS
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

---

## Written, measured, and parked on a PIN (frankS, 2026-08-31)

**The blocker this ticket was filed under is gone** —
`feature-nested-routine-fixed-array-capture` landed this morning, so a nested
`PersistParamRow` capturing the 21 fixed-size staging arrays now compiles. The
collapse is written and green. It is parked on a *different* dependency, which
is sequencing rather than engineering.

### What exists

`devdocs/progress/patches/refactor-a-durable-param-row-collapse.patch`, 399
lines, applies cleanly to `962170246`. It:

- adds nested `procedure PersistParamRow(procIdx, i: Integer)` to
  `ParseSubroutine`, carrying the canonical note and the guard
  (`procIdx < 0` / `i` out of range → Exit) exactly once;
- replaces all three hand-copied blocks with one call each, keeping each site's
  measured history as its comment;
- moves the canonical note to the body path's call.

Verified: `make compiler/pascal26` converges in 1 round to `0a7978a21cbc`;
`test_param_row_external_forward_fail` still reports exactly 3 refusals with
`ext` and `fwd` both named; `test_param_row_external_forward_ok` prints the
same line before and after.

### Two things it turned up on the way, both landed already

1. **`f8442bc59` — the lift's capture limit was a literal 16**, while the
   staging arrays and `TProc.Params` are both `MAX_PROC_PARAMS = 32`. The first
   build after the collapse died on that guard, not on any array bound. Raised
   to the real bound, with `test/test_nested_capture_param_bound.pas` (20 scalar
   + 20 array captures; `pinned` refuses the scalar half, 40 is still refused).
2. **`962170246` — the body path wrote `ProcParamProcSig` with NO `procIdx >= 0`
   guard**, alone among that copy's writes; it indexed
   `ProcParamProcSig[-MAX_PROC_PARAMS + i]` whenever `procIdx` was -1. The
   collapse retires it by construction, since the guard is now in one place.
   Same commit adds `bodyDef` / `bodyRec` so the default and rec-id columns are
   asserted on all three paths, not just the pointee.

### Why it cannot land yet, measured

```
$ stable_linux_amd64/default/pinned compiler/compiler.pas /tmp/x
pascal26:628: error: nested routine: capture of fixed-size array 'pconst'
not yet supported
```

`pinned` predates fixed-array capture, so `gate.sh quick`'s pinned-seed
fixedpoint goes **RED** and the tree would be unbuildable from the pin for
every lane, not just this one. This is stage 2 needing stage 1 **pinned**
rather than merely merged — one of the three things CLAUDE.md says the
coordinator sequences, and a `make pin` is the owner's call, not mine.

**So: needs a pin, not more work.** After any `make stabilize-fast && make pin`
that blesses a compiler at or after `50fcbddef`, apply the patch, rebuild,
`gate.sh quick`, and resolve. Nothing else is outstanding.

### One residual, deliberately not folded in

The body path did NOT write `ProcParamRecId` for an **open array of records**
(`const items: array of TRec`) — its arm sits behind an `else if` after the
`parr and tyRecord` case — while the other two copies did. The collapse makes
all three agree, which is a real behaviour change on the body path and is why
the self-host fixedpoint mattered here (`array of const` is all over
`compiler/`; it converged in 1 round, byte-identical). Probed for an observable
delta and found none, because the shape it would show up in is **already broken
on both sides**:

```pascal
function pick(const items: array of TA): Integer; overload;
function pick(const items: array of TB): Integer; overload;
```

`pinned` and the collapsed compiler both print `7` and then SEGFAULT on the
second call; FPC prints `7 5`. Pre-existing, unchanged by this work, and not
this ticket's job — filed separately.
