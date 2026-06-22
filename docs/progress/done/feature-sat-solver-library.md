# SAT solver library — DPLL over CNF (known-instance test app)

- **Type:** feature
- **Status:** done — green on pinned v34
- **Owner:** —
- **Opened:** 2026-06-19
- **Relation:** demo-eligible-as-library from idea-demo-app-candidates. Sibling
  to feature-json-library et al. **Strong pressure on the set lane** — see
  feature-language-gaps-from-demos Gap 1 (`set of` from runtime values /
  Include/Exclude); a SAT solver naturally wants runtime-built sets of
  literals/assignments. Own unit, no FPC equivalent.

## Background (so scope is clear)

- **SAT** = boolean satisfiability: is there a true/false assignment satisfying a
  formula? First NP-complete problem (Cook–Levin).
- **CNF** = conjunctive normal form: AND of clauses, each clause an OR of
  literals (`x` or `¬x`). Standard solver input.
- **DIMACS CNF** = the canonical text format (`p cnf <vars> <clauses>`; each
  clause = space-separated ints terminated by `0`; negative int = negated var).
- **DPLL** = backtracking search + **unit propagation** + pure-literal
  elimination. ~Small core. (CDCL is the modern successor — out of scope here.)
- Industry use: EDA / chip verification, formal verification & model checking,
  **package dependency resolution** (apt/dnf/cargo), AI planning, cryptanalysis.

## Goal

A `SAT` unit: parse DIMACS CNF, run DPLL, return SAT + a satisfying model or
UNSAT.

## Surface (sketch)

- `function ParseDIMACS(const s): TCNF;`
- `function Solve(const cnf; var model): TSatResult;`  (`srSat` / `srUnsat`)
- model = per-variable assignment

## Coverage

backtracking recursion · **sets** (clauses / current assignment — the lane chess
deliberately avoided) · dynamic arrays (clause DB) · short-circuit guards ·
managed-string DIMACS parsing.

## Acceptance / oracle

- Known instances: small satisfiable formulas (model verified by substitution),
  classic **UNSAT** instances (pigeonhole `PHP(n+1,n)`).
- Deterministic decision order → SAT/UNSAT + (for SAT) a verifiable model,
  byte-identical across targets.
- Demo: `examples/sat/` solves a bundled `.cnf` set, prints results.

## Constraints

Own `.pas` unit; no port; no self-host / cross regression. Likely wants the set
lane (Gap 1) for a clean implementation — until then, a bitmask fallback as in
the sudoku/chess demos.

## Log
- 2026-06-19 — Opened from the demo/library organization pass. Background section
  added (user asked what SAT/CNF/DPLL are and where they come from — logic /
  theorem proving, 1960–62, not databases).
- 2026-06-22 — **Implemented** (track B): `lib/rtl/sat.pas` (DIMACS parser +
  DPLL with unit-propagation-via-forced-literal recursion + backtracking) and
  oracle `examples/sat/satdemo.pas` (trivial SAT, a unit-propagation chain, a
  small UNSAT, and pigeonhole PHP(3,2)/PHP(4,3) UNSAT; SAT models verified by
  substitution). Sets avoided (tri-state Integer array). No `set of` gap hit.

  Two compiler bugs surfaced and were dodged/filed:
  1. **dynarray-as-record-field is broken** → `TCNF` record was abandoned in
     favour of module-global state (zlib pattern). Filed
     bug-dynarray-in-record-corrupt (clean minimal repro, FPC-verified).
  2. **PXX still miscompiles the finished unit** even with globals: `LoadDIMACS`
     loses a local counter increment (`clauseCount` stays 0) — a deterministic,
     FPC-verified case of the layout-sensitive codegen bug. Fails on both
     `dc11a9c` and v33. Folded into bug-impl-prescan-codegen-regression as a
     second repro that reframes its root cause (pre-existing slot/offset
     allocation bug, not the `7ba91bf` pre-scan).

  **Was blocked**, now resolved — corrected diagnosis:
  - The `LoadDIMACS clauses=0` was **not** the impl-prescan/slot-offset bug I
    first claimed. It was a compiler **name-resolution** bug: the local
    `clauseCount` was shadowed by the same-named paramless function `ClauseCount`,
    so bare reads resolved to the function. Track A fixed it (0e0bbdb, "local
    variable shadows same-named paramless function"), pinned **v34**.
  - DPLL recursed via a bare `DPLL`, which under the modern dialect (and FPC
    objfpc) reads the result variable, not a recursive call. Fixed in this lib to
    `DPLL()` (commit on this branch). My-code issue, not a compiler bug.
- 2026-06-22 (later) — **DONE.** With v34 + `DPLL()`, `examples/sat/satdemo.pas`
  runs `ALL OK` on the pinned compiler (PHP(3,2)/PHP(4,3) UNSAT, SAT models
  verified). Wired into `make lib-test` (green) + `make demos`.
