# sat DPLL: bare paramless recursion needs `DPLL()` after the paramless flip

- **Type:** library fix (**Track B**) + flip-consequence note (Track A)
- **Status:** backlog — **not a compiler bug** (reclassified 2026-06-22)
- **Owner:** — (Track B owns the one-line sat fix)
- **Opened:** 2026-06-22
- **Relation:** consequence of [[bug-bare-function-name-call-vs-resultvar]] (the
  paramless flip, `db99145`); surfaced while closing
  [[bug-impl-prescan-codegen-regression]].

## TL;DR

`lib/rtl/sat.pas` `DPLL` recurses via **bare `DPLL`** (`if DPLL then ...`). As of
the paramless flip (`db99145`, today), a bare paramless function name read inside
its own body is the **result variable**, not a recursive call — matching FPC
default/objfpc. So `DPLL` no longer recurses: the search runs one level, reads an
uninitialised `Result`, and returns garbage (every satisfiable instance →
`UNSAT`). **There is no codegen bug.** The fix is one character class:

```pascal
if DPLL() then begin Result := True; Exit; end;   { add the parens, ×3 sites }
```

Verified: with `DPLL()` the solver is fully correct on PXX v34 (every bundled
instance, SAT + UNSAT, matches expectation).

## How it was (mis)diagnosed and corrected

1. After the name-collision fix, clause counts were right but every SAT instance
   reported `UNSAT`. First theory: a dyn-array codegen bug (paramless recursion
   saving a global dyn-array into a local `pre` + backtrack restore).
2. Minimal **param-based** backtracking repro: PXX == FPC (correct). Only the
   **paramless** shape diverged → pointed at the flip, not dyn-arrays.
3. `function Down: Boolean; ... if Down then ...` across FPC modes:
   - `fpc` / `fpc -Mobjfpc`: depth 1 — bare `Down` = result var (no recursion).
   - `fpc -Mdelphi`: depth 4 — bare `Down` recurses.
   So FPC's rule is **mode-dependent**; PXX targets objfpc semantics, which the
   flip now matches.
4. The earlier "`fpc -Mobjfpc` solves sat3" observation was an **uninitialised
   result-var read** that happened to be non-zero (`dpllCalls=1`, i.e. no
   recursion) — luck, not a solve. sat.pas is broken under objfpc too; it only
   worked on **pre-flip PXX** (where bare paramless = recurse, Delphi-like).

## Why Track B hit it now

`sat.pas` was committed (`7b346c4`, 12:18) after the flip (`11:53`) but Track B
builds against the **pinned** binary, which was **v33 (pre-flip)** at the time —
so `DPLL` recursed there (only the name collision broke it). Re-pinning **v34**
(post-flip + collision fix) fixed the collision but made the bare-`DPLL`
recursion a result-var read. Net: the recursion idiom that worked on v33 is
invalid on v34.

## The rule going forward (both tracks)

A **paramless** routine must use `F()` to recurse (and `@F` for a pointer); a
bare `F` is now the result variable, per FPC objfpc. This is the same interim
rule already documented for the compiler sources. **Blast radius in the libs is
just `sat.pas` `DPLL`** — `make lib-test` is green on v34 (zlib `BytePos`, json
`JSONObject`, etc. are *cross-function* bare calls, which are unaffected; only a
bare name inside its *own* body changed meaning). `examples/` self-recursive
paramless routines (if any) should be spot-checked by the demos lane.

## Action

- **Track B:** `lib/rtl/sat.pas` — change the three `if DPLL then` to
  `if DPLL() then`. Re-run `examples/sat/satdemo.pas` (expect `ALL OK`).
- No compiler change. No re-pin needed (v34 already carries the flip).

## Log
- 2026-06-22 — Filed as a suspected dyn-array codegen bug, then **reclassified**:
  root cause is the paramless flip (`db99145`), not codegen. One-line Track-B fix
  (`DPLL` → `DPLL()`), verified correct on v34. Decision (with user): keep the
  flip (FPC-objfpc faithful); Track B migrates bare paramless recursion to `F()`.
