# Demo — RPN / expression calculator (mini spreadsheet)

- **Type:** feature
- **Status:** done — expression-evaluator core (commit 29e19cc); spreadsheet layer not built (was optional)
- **Owner:** —
- **Opened:** 2026-06-19
- **Relation:** demo-class survivor from idea-demo-app-candidates (was catalog
  #4). Could lean on feature-bignum-library for exact-integer mode. Platonic
  source.

## Goal

An expression calculator: parse infix expressions (Pratt or shunting-yard) and/or
RPN, evaluate with an operator/function table. Optional mini-spreadsheet layer:
named cells referencing each other, recomputed on change.

## Surface / shape

- tokenizer + parser (managed strings)
- **procedural-type op table** (binary ops, functions like `min`/`max`/`gcd`)
- evaluator over an expression tree (records + recursion)
- optional: cell map (collection) + dependency recompute

## Coverage

managed strings (parse) · records + dynamic arrays (AST) · **procedural types**
(op/function table) · recursion (eval) · collections (spreadsheet cells) ·
short-circuit. Integer-deterministic core; float optional, kept out of the
oracle path.

## Acceptance / oracle

- Fixed expression set → exact integer results, byte-identical across targets
  (e.g. `2+3*4`, `gcd(48,36)`, nested parens, RPN forms).
- Spreadsheet slice: a fixed cell graph → fixed recomputed values.
- Demo: `examples/calc/` evaluates a bundled set; optional REPL over serial.

## Constraints

Platonic source; no compiler changes; ESP32-fit. No self-host / cross
regression.

## Log
- 2026-06-19 — Opened in the demo-ticket organization pass.
- 2026-06-22 — **DONE** (track B), commit 29e19cc: `lib/rtl/calc.pas` integer
  expression evaluator — one-pass recursive-descent (no AST, to dodge the
  dynarray-in-record codegen bug), precedence/parens/unary, gcd/min/max/pow/abs,
  errors on syntax + div/mod-by-zero + unknown fn + trailing junk. Oracle
  `examples/calc/calcdemo.pas` runs `ALL OK` on pinned v33; wired into
  `make lib-test` + `make demos`. Used the json-style reader class (zero-init
  fields), which compiles cleanly — unlike the module-global `sat` unit that hit
  the layout-sensitive codegen bug. **Not done:** the optional mini-spreadsheet
  layer (named cells + dependency recompute) — file a follow-up if wanted.
