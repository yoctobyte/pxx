---
summary: "FPC can no longer compile compiler.pas — 8 errors of accumulated seed drift"
type: regression
track: A
prio: 55
---

# FPC seed drift: `fpc compiler/compiler.pas` fails with 8 errors

- **Type:** regression (cold-start bootstrap path) — **Track A** (`compiler/**` drift)
- **Status:** done
  is this really" below.
- **Filed:** 2026-07-31 by Track T (face 2) from tstate `open_regressions`.
- **Job:** `fpc-bootstrap#src:compiler/compiler.pas` — open since 2026-07-22.

## Current failure (measured at HEAD, not copied from the stale record)

```
fpc -Mobjfpc -O2 -Tlinux -Px86_64 compiler/compiler.pas
```

```
clexer.inc(207,14)  Error: Identifier not found "CLexLineMarker"
clexer.inc(440,29)  Error: Identifier not found "DbgMarkTokFile"
clexer.inc(441,8)   Error: Identifier not found "DbgMarkTokFile"
clexer.inc(441,33)  Error: Identifier not found "DbgFileId"
parser.inc(840,10)  Error: Function is already declared Public/Forward "PyMakeNone:LongInt;"
parser.inc(842,10)  Error: Function is already declared Public/Forward "PyCallMeth1(LongInt;const AnsiString;LongInt;LongInt):LongInt;"
parser.inc(4634,24) Error: Identifier not found "PyMakeTupleFrom"
parser.inc(8633,33) Error: Illegal expression
parser.inc(8633,33) Fatal: Syntax error, ";" expected but "," found
```

Three distinct drift shapes, all "PXX is laxer than FPC":

1. **Use-before-declaration** — `CLexLineMarker`, `DbgMarkTokFile`, `DbgFileId`,
   `PyMakeTupleFrom` are referenced above their declaration/forward. PXX resolves
   these; FPC needs a `forward` (or the routine moved and its forward didn't).
2. **Duplicate forward** — `PyMakeNone` / `PyCallMeth1` are forward-declared
   twice (parser.inc:840,842). PXX tolerates the redeclaration, FPC rejects it.
   Likely two agents adding the same forward independently.
3. **Trailing comma / expression syntax** at `parser.inc:8633` — needs a look;
   FPC's parser gives up there, so error 3 may be masking more behind it.

Each is trivial the day it lands and archaeology later — which is exactly the rot
this canary exists to catch.

## The recorded bisect is WRONG — do not chase `b1976742df2c`

tstate carries `bad=b1976742df2c57eca84cd069d4e8b16a43a204cf`,
`good=6f73c5a88bef`, 1 commit in range. That commit is
*"fix(core): {$Q+} narrow-destination overflow checks on i386/arm32/riscv32"* and
touches only `ir_codegen386.inc`, `ir_codegen_arm32.inc`,
`ir_codegen_riscv32.inc`, `rv32enc.inc`, and four Makefile hunks that add cross
test lines. **None of it can produce a `clexer.inc` / `parser.inc` identifier
error.** It was a true bisect on 2026-07-22 for whatever failed *then*; nine days
of further drift have landed on top, and the watcher does not re-bisect a job
that is already open.

Treat this as **cumulative drift with no single culprit**, not a one-commit
revert. Fix forward: add the missing forwards, drop the duplicate pair, look at
8633.

## How urgent is this really

Honestly: **not very, and the tooling says so.** `testmgr.py`'s
`fpc_canary_job()` sets `advisory = True`, and its own docstring reads *"a red
here is a notice for Track A, not a gate on anyone's push."* Nothing day-to-day
touches the FPC seed — every normal build starts from the self-hosted binary,
which is why this path rots silently in the first place.

It is filed urgent because it is the **cold-start path**: the only way to rebuild
on a box with no blessed `pascal26`, and the escape hatch if a self-hosted binary
is ever lost. It costs little now and is expensive to reconstruct later. The
`prio: 55` is the honest number; the folder reflects "don't let this sit another
nine days", not "stop what you are doing".

## Track T follow-up (separate, T's own tooling)

The watcher's `open_regressions` record went stale without any signal: the
bisected `bad` sha stayed pinned while the actual failure signature changed
underneath it. Worth teaching twatch to re-bisect (or at least re-hash the log
tail and flag a mismatch) when an open regression's output stops matching what
was bisected. That is a Track T tooling change, filed separately — it does not
belong to this ticket.

## Log
- 2026-07-31 — resolved, commit 8dc18d143.
