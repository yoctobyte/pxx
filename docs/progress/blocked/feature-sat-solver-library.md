# SAT solver library — DPLL over CNF (known-instance test app)

- **Type:** feature
- **Status:** backlog
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
