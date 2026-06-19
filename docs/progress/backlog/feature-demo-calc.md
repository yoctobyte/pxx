# Demo — RPN / expression calculator (mini spreadsheet)

- **Type:** feature
- **Status:** backlog
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
