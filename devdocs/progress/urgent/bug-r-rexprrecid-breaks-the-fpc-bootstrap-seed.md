---
track: R
prio: 80
type: bug
blocked-by: []
summary: "compiler/rparser.inc:1293 calls RExprRecId, defined at :1507. pxx resolves across the unit so `make compiler/pascal26` is green; FPC resolves in SOURCE ORDER, so the bootstrap seed build fails with `Identifier not found \"RExprRecId\"` and master cannot be built from FPC. Invisible to the documented per-fix loop by construction; caught by gate.sh quick's seed canary and by tools/forwardlint.py. One-line fix: a forward declaration."
status: urgent
owner: unassigned
---

# RExprRecId breaks the FPC bootstrap seed

Found by frankA (Track A) while gating an unrelated `symtab.inc` fix — the gate
went RED on this and only this. **Not filed as a Track A change**: the fix is one
line in `compiler/rparser.inc`, which is Track R's file, and Rust work looked
live there (`fcfe1cba1`), so it is handed over rather than taken.

```
rparser.inc(1293,12) Error: Identifier not found "RExprRecId"
compiler.pas(2111) Fatal: There were 1 errors compiling module, stopping
```

`RExprRecId` is used at `rparser.inc:1293` and defined at `:1507`.

## Why nothing caught it before the gate

This is the exact class CLAUDE.md warns about: **pxx resolves names across a
whole unit, FPC resolves them in source order, and FPC is what bootstraps this
compiler.** So `make compiler/pascal26` — the documented per-fix loop, and a real
byte-identical self-host fixedpoint — is green while the seed build is broken.
The loop cannot see it by construction.

Severity is "master cannot be built from a clean FPC bootstrap", not "master is
broken": every existing binary keeps working, self-host keeps converging, and
`--tier quick` passes. It blocks bootstrapping from source and it fails any lane's
`gate.sh quick`, which is required before a pin — so **nobody can pin until this
lands.**

## Fix

Add `function RExprRecId(...): Integer; forward;` above the first caller in the
same file, matching the existing convention (`pasparser_generic.inc` carries a
block of these with a comment explaining why). Keep it **above the first caller**,
not merely somewhere in the file — a forward that a later refactor lifts a caller
above is re-broken and reads as already handled.

## Verify with the linter, not the error message

`python3 tools/forwardlint.py` expands `compiler.pas`'s include chain in FPC's
order and reports **every** such call in one pass; it takes ~4 seconds. FPC
reports one batch and aborts, so fixing exactly the names it printed and
rebuilding is whack-a-mole — measured on 2026-08-29, four missing forwards took
three RED gate cycles that way and one lint pass to finish. Run the lint to zero
FAILs rather than rebuilding until the message goes away.

Related: [[bug-a-fpc-seed-drift-emitasmx64-forward]],
[[decide-should-the-fpc-seed-canary-be-in-the-mandatory-loop]] (this is a fourth
measured instance for that decision).
