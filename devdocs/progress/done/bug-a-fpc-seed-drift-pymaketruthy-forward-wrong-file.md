---
summary: "FPC cold-start broken again: PyMakeTruthy is used in parser.inc but forward-declared in pyparser.inc, which is included 14 lines later. Verified one-line-move fix."
type: regression
track: A
prio: 60
---

# FPC seed drift: `PyMakeTruthy` forward is in the wrong file

- **Type:** regression, cold-start bootstrap path — **Track A** (`compiler/**`)
- **Filed:** 2026-08-01 by Track T from the `fpc-bootstrap` canary.
- **Advisory**, per `testmgr.fpc_canary_job()`: a red here is a notice for
  Track A, not a gate on anyone's push. Nothing day-to-day uses the FPC seed —
  which is exactly why it rots silently.
- **Culprit:** `01b0b32f4` *"fix(N): bool() must consult `__bool__`/`__len__`,
  via the shared truthiness rule"*. Broken at `2a3fd4404bdb`, still broken at
  `f5de12d6e`.

## The failure

```
$ fpc -Mobjfpc -O2 -Tlinux -Px86_64 -FU/tmp/x -FE/tmp/x -o/tmp/c compiler/compiler.pas
parser.inc(10074,19) Error: Identifier not found "PyMakeTruthy"
compiler.pas(1031) Fatal: There were 1 errors compiling module, stopping
```

## Why — an ordering problem, not a missing forward

The forward **exists**, in the wrong file:

| | |
|---|---|
| used at | `parser.inc:10074` — included by `compiler.pas:86` |
| forward at | `pyparser.inc:181` — included by `compiler.pas:100` |
| defined at | `pyparser.inc:1827` |

That forward fixes the use-before-definition *within* `pyparser.inc`; its own
comment says so and cites the earlier drift ticket. But the new use is in
`parser.inc`, **14 includes earlier**, where the identifier is not yet known.

The project already has the right home for this. `compiler.pas:68-72`:

```pascal
{ PXX_NEED_FORWARDS := FPC or PXX_REQUIRE_FORWARD. PXX without it prescans and
  skips this; placed before symtab.inc so it is above every use it covers. }
{$ifdef FPC}{$define PXX_NEED_FORWARDS}{$endif}
{$ifdef PXX_NEED_FORWARDS}{$include forwards.inc}{$endif}
```

`forwards.inc` exists precisely for declarations FPC needs and PXX does not, and
it is included *before* everything. It does not currently mention
`PyMakeTruthy`.

## Fix — MOVE the forward, do not add one (verified)

The obvious patch does **not** work. Adding it to `forwards.inc` while leaving
`pyparser.inc:181` in place gives:

```
pyparser.inc(181,10) Error: Function is already declared Public/Forward
                            "PyMakeTruthy(LongInt):LongInt;"
```

— the duplicate-forward shape FPC rejects and PXX tolerates, already on record
as drift shape 2 in the earlier seed-drift ticket. So:

1. add to `compiler/forwards.inc`:
   `function PyMakeTruthy(n: Integer): Integer; forward;`
2. **delete** `compiler/pyparser.inc:181` (the now-duplicate forward).

**Verified on this box** — with exactly those two edits, `fpc … compiler.pas`
exits **rc=0**, the cold-start path is restored. Reverted afterwards; nothing
committed to `compiler/**` from Track T.

Safe for PXX: it prescans and skips `forwards.inc` entirely
(`PXX_NEED_FORWARDS` is FPC-only), so removing the in-file forward costs it
nothing.

## The recurring pattern is the real story

This is the **third** instance today of one shape: a helper is added and used
above (or before) its declaration, PXX resolves it because it prescans, FPC
does not, and only the advisory canary notices.

- morning: `28b15ad3f` *"restore FPC bootstrap — helpers were declared AFTER
  their first use"*
- earlier: the `regression-fpc-seed-drift-b1976-stale` batch
- now: this one

The mechanism to prevent it already exists and works; what is missing is that a
**cross-file** use has to be registered in `forwards.inc`, and nothing enforces
that at the time of writing. A cheap guard would be worth more than the next
three fixes: the canary already runs in `native`/`limited`/`full`, so the
feedback exists — it is just advisory, so it is easy to walk past.

---

## FIXED by Track A — `9d2d98856` (verified by Track T, 2026-08-01)

*"fix(A): forward-declare PyMakeTruthy in parser.inc — FPC seed build was red"*.

Verified on this box at HEAD: `fpc -Mobjfpc -O2 -Tlinux -Px86_64 …
compiler/compiler.pas` reports **0 errors**. The cold-start path is restored.

Track A forward-declared it **in `parser.inc`**, above the use, rather than
moving it to `forwards.inc` as this ticket proposed. Both work and the canary is
green either way, so this is not a correction — but the difference is worth
recording, because the two placements are not equivalent going forward:

- `forwards.inc` is included **FPC-only** (`compiler.pas:72`,
  `PXX_NEED_FORWARDS`), so declarations there cost PXX nothing and sit above
  every use by construction.
- a forward in `parser.inc` is compiled by **both** front ends and only covers
  uses below that point in that file.

Neither is wrong. The one that matters is that the *next* cross-file helper hits
the same wall, which is the open half of this ticket and is not addressed by
either placement: **nothing enforces registering a cross-file use at the time of
writing**, and the canary that catches it is advisory by design.

## Log
- 2026-08-01 — resolved, commit 9d2d98856.
