# Unit impl-section pre-scan silently miscompiles routines (zlib decode broken)

- **Type:** bug (compiler) — **Track A**
- **Status:** **DONE** — fixed + re-pinned v34; `make lib-test` GREEN on master.
- **Severity:** was CRITICAL (silent miscompile shipped in v33). Resolved.
- **Opened:** 2026-06-22
- **Owner:** — (Track A / "sis")
- **Found by:** Track B, while wiring the new `json` library into `lib-test`.

## Update 2026-06-22 (post v33 pin)

v33 was pinned before this was fixed, so master's `make lib-test` is RED right
now (png: `decode=truncated stored data`). Cannot un-pin to a pre-`7ba91bf`
commit because `json`/`bignum` libs need `obj.Free` (562eb95) + bare `Copy`
(dd706ff), which are newer than `7ba91bf` — **forward fix of `7ba91bf` only**,
then re-pin v34.

Mechanism (refined twice):

1. **Not a block-type misroute.** Instrumenting `InflateRaw` shows the png IDAT
   stream legitimately *is* a stored block: `bfinal=1 btype=0 gBitPos=19`. The
   failure is the stored-data bound check `BytePos + len > Length(gData) - 4`
   (zlib.pas:448) wrongly firing — i.e. one of `BytePos` (paramless fn call),
   `len`, `Length(gData)`, or the comparison is computed wrong.

2. **Layout-sensitive latent codegen bug, not new wrong logic.** Adding a single
   `writeln(...)` into `InflateRaw` makes even the *GOOD* compiler (`dc11a9c`)
   miscompile and fail identically. So `7ba91bf` does not introduce wrong logic
   per se — it shifts the decl/codegen layout of the unit's implementation
   section enough to *expose* a pre-existing latent miscompile (likely stack-slot
   / temp / offset allocation around `InflateStored`). This explains why
   `make test` + self-host stayed byte-identical, and why a small single-unit
   reduction is elusive: any layout-changing edit moves the bug.

   Fix implication: look at how the two-pass impl pre-scan affects routine
   local-var / temp **offset allocation** (not name resolution). The underlying
   defect is probably fragile slot/offset assignment that `7ba91bf` merely
   re-triggered.

`test/lib_zlib.pas` (small inputs) still passes → size/shape-dependent. A minimal
single-unit reduction is still TODO and may be impractical given the layout
sensitivity; the live png repro below is reliable.

## Update 2026-06-22 (root cause reframed — NOT just 7ba91bf)

Building the `sat` library turned up a **second, deterministic, FPC-verified**
manifestation that reframes the root cause:

- `lib/rtl/sat.pas` `LoadDIMACS` reliably miscompiles: a local `Integer`
  counter (`clauseCount`) is never incremented (`clauseCount := clauseCount + 1`
  reads back 0), while a sibling counter (`litCount`) works. FPC compiles the
  identical source correctly. Repro: `compiler/pascal26 examples/sat/satdemo.pas`
  (or any driver) → every formula reports `0 clauses` and wrong SAT/UNSAT;
  `fpc -Mobjfpc` → correct.
- It fails on **both** `dc11a9c` (pre-`7ba91bf`) **and** v33. So this victim is
  **not** a `7ba91bf` regression — it is a **pre-existing latent codegen bug**.
- It is **global-layout-sensitive**: extracting `LoadDIMACS` verbatim into a
  *small* unit compiles correctly; only the *full* `sat.pas` symbol layout
  triggers it. Likewise, adding a `writeln` to zlib flips even the "good"
  compiler (noted below).

**Conclusion:** the real defect is fragile **local-variable / temp slot/offset
allocation** in unit-procedure codegen. `7ba91bf` did not introduce it — it
shifts decl/codegen layout, changing *which* units land on the bad allocation.
zlib was "safe" under `dc11a9c` and "unsafe" under `7ba91bf`; `sat` is "unsafe"
under both.

**Fix-strategy implication:** reverting/adjusting `7ba91bf` may restore a safe
layout for zlib/png (unblock the gate) but will **not** fix the underlying bug —
`sat` and future libs can still hit it. The durable fix is in slot/offset
allocation, not the pre-scan. A good gate test: compile a unit whose procedure
has ~10 locals + nested if/else with `SetLength` on module-global dynarrays in
both branches, and check a computed counter against FPC.

Deterministic repro (better than the png one — no instrumentation needed):
```sh
stable_linux_amd64/default/pinned examples/sat/satdemo.pas /tmp/s && /tmp/s
#   -> "0 clauses", FAILs;   fpc -Mobjfpc agrees the source is correct
```

## Summary

Commit **`7ba91bf`** ("feat(parser): extend declaration pre-scan to unit
implementation sections") introduces a **silent codegen regression**: a routine
in a unit's *implementation* section can be miscompiled. No diagnostic — the
program builds and runs but computes wrong results.

Concrete victim: `lib/rtl/zlib.pas` `InflateStored`. PNG decode of a stored
(uncompressed) deflate block now fails with `decode=truncated stored data`,
where the bound check `if BytePos + len > Length(gData) - 4` (zlib.pas:448)
wrongly fires. `lib/rtl/png.pas` decode is broken as a result; the curious part
is that `test/lib_zlib.pas`'s own "stored roundtrip" case still passes, so the
miscompile is data/size- or shape-dependent, not a blanket failure of the
routine.

This passed Track A's gate: `make test` + self-host are byte-identical (the
compiler still compiles *itself* correctly), so nothing caught it. It only shows
up compiling third-party units with implementation-private helpers — i.e. the
Track B libraries.

## Bisect (clean, via `git archive` to /tmp — working tree untouched)

| commit   | result | note |
|----------|--------|------|
| `dc11a9c` | GOOD (png `2x2`) | declaration pre-scan, whole-section (program) |
| `38f9b75` | (skipped — no compiler change; demos) | |
| **`7ba91bf`** | **BAD** (`decode=truncated stored data`) | **extend pre-scan to unit impl sections** |
| `a50bbd5` | BAD | |
| `a9251ff` (HEAD) | BAD | |

`7ba91bf`'s only compiler change vs the last GOOD point is `compiler/parser.inc`
(+47 lines). `38f9b75` between them touches no compiler code.

## What `7ba91bf` changed (suspect surface)

`ParseUnit` now runs a two-pass over the implementation decl loop: pass 1
registers impl-private routine headers + skips bodies, pass 2 replays them.
Recorded spans use a region of the shared `DeclItem` arrays based at the
caller's `DeclItemCount` (`savedBase`), restored on exit. Likely fault areas:
- span region accounting (`savedBase` / `DeclItemCount`) corrupting a later
  routine's recorded body or local/var offsets;
- a const/var in the impl section resolving differently on the replay pass
  (e.g. the `65535` literal or `Length(gData)` in `InflateStored`);
- body replayed against stale scope so an expression's codegen differs.

## Repro

```sh
# GOOD baseline (pinned):
make lib-test                       # png line -> "2x2 ..."  PASS

# BAD (current master self-hosted):
make bootstrap                      # builds compiler/pascal26 at HEAD
compiler/pascal26 test/lib_png.pas /tmp/png && /tmp/png
#   -> line 4 prints  decode=truncated stored data   (want: 2x2)

# Bisect a single commit cleanly:
rm -rf /tmp/bx && mkdir /tmp/bx && git archive 7ba91bf | tar -x -C /tmp/bx
( cd /tmp/bx && make bootstrap )
/tmp/bx/compiler/pascal26 test/lib_png.pas /tmp/p && /tmp/p   # BAD
```

(Same `lib/rtl/zlib.pas` source compiled both ways — working tree unmodified —
so the divergence is purely compiler codegen.)

## Impact / why it blocks re-pin

The workflow is: Track A re-pins the stable binary before a Track B push. If the
stable is re-pinned at any commit >= `7ba91bf`, `make lib-test` breaks (png) and,
worse, *any* Track B unit with implementation-private helpers may be silently
miscompiled. Re-pin must wait for a fix (or pin a commit < `7ba91bf`, which then
lacks `obj.Free`/bare `Copy` that the new `json` lib needs — so a fix is the real
unblock).

## Not the basic mechanism

A trivial impl-only forward-called helper compiles + runs correctly on HEAD:

```pascal
unit u; interface function Run(n: Integer): Integer; implementation
function Run(n: Integer): Integer; begin Result := Helper(n) - 4; end;
function Helper(n: Integer): Integer; begin Result := n * 2; end; end.
```
`Run(10)` = 16 (correct on HEAD; v32 errors `undefined variable (Helper)`, as
expected pre-feature). So the feature's happy path works — the regression is
**shape/scale-dependent** (a specific routine among many in a large unit such as
`zlib.pas`), consistent with span-region/`savedBase` accounting that only goes
wrong past some decl count or nesting. Minimization should scale up #impl
routines / locals rather than chase the 2-function case.

## Suggested next steps (Track A)

1. Minimize: a small unit with an impl-only helper that mis-evaluates an
   arithmetic/`Length()` expression — start from `InflateStored`'s shape.
2. Inspect `savedBase` / span-region restore in the new `ParseUnit` two-pass.
3. Add a Track-B-style codegen regression to `make test` (compile a unit with
   impl-only helpers and check a computed result) so this class is gated.

## Log
- 2026-06-22 — Filed by Track B. Bisected to `7ba91bf`; png/zlib decode repro.
  Blocks re-pin needed for `feature-json-library` lib-test wiring.
- 2026-06-22 — **ROOT CAUSE FOUND + FIXED (Track A).** Not slot/offset allocation
  and not `7ba91bf` — a **name-resolution** bug. PXX is case-insensitive, so a
  local variable collides with a *paramless function* of the same name (sat:
  local `clauseCount` vs function `ClauseCount`; zlib: a counter vs a helper).
  Both the expression-read (`ParseFactor`) and the statement-assignment
  (`ParseStatementAST`) resolved the bare name to a **CALL of the function**
  instead of the local variable, so the local's reads/writes silently vanished —
  `clauseCount := clauseCount + 1` compiled to `gNumClauses := ClauseCount()`
  (always 0). Confirmed via `--dump-ir` (the store's RHS was `call a=145`, not
  `load_sym [sym=clauseCount]`). `7ba91bf` only shifted unit layout → changed
  *which* units happened to contain a collision (consistent with the bug
  reproducing on `dc11a9c` too, and with `make test`/self-host staying
  byte-identical: `compiler.pas` has no such collision).
  **Fix:** guard both bare-paramless-call branches with `idx < 0` / `si < 0` (no
  variable of that name in scope) so an in-scope variable shadows the function
  (correct Pascal scoping); the function is still called when nothing shadows it.
  Commit `5153dd7` (parser.inc) + regression `test/test_local_shadows_func.pas`.
  Gate: `make test` + fpc-check byte-identical, cross-bootstrap (i386/aarch64/
  arm32) byte-identical. **png decode → `2x2`; `make lib-test` GREEN; re-pinned
  v34** (handed to Track B). The ticket's pre-scan/`savedBase` theory is retired.
- 2026-06-22 — Residual: the sat *solver* (DPLL) still diverges PXX-vs-FPC on a
  satisfiable instance (`sat3` → PXX `UNSAT`, FPC `SAT`) — a **separate** codegen
  bug, NOT this collision (no name clash in DPLL/Solve/ClauseStatus). Cleanly
  isolated to a standalone FPC-vs-PXX repro; filed as
  [[bug-dpll-recursion-global-array-miscompile]]. The sat-library ticket stays
  blocked on that, not on this one.
