# Demo — Lisp / Scheme interpreter

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-19
- **Relation:** demo-class survivor from idea-demo-app-candidates (was catalog
  #3). Interpreter family (demo, not library). Flagship-tier coverage, larger
  than the others. Sibling to feature-demo-vm.

## Goal

A small Lisp/Scheme: S-expression reader, evaluator with environments and
closures, core special forms (`quote`, `if`, `lambda`, `define`, `let`), and a
builtin set (arithmetic, `cons`/`car`/`cdr`, comparisons, `list`). Tail behavior
best-effort.

## Surface / shape

- value = tagged union / small class hierarchy: number / symbol / cons / closure
  / nil (exercises **variant or class/VMT** lane)
- reader (managed strings → tree), `Eval(expr, env)`, environment as a
  collection / linked frames
- builtins registered via **procedural types**

## Coverage

deep recursion (eval) · collections / hashing (symbol table, environments) ·
managed strings (reader/printer) · variant or class hierarchy · procedural types
(builtins) · dynamic arrays. GC/arena pressure is a real-world stressor.

## Acceptance / oracle

- An eval suite (fixed programs → expected printed results), byte-identical
  across all targets — e.g. recursive `factorial`, `map`, closures capturing
  state.
- Demo: `examples/lisp/` runs the suite; optional REPL over stdin/serial.

## Constraints

Platonic source; no compiler changes; integer core for the oracle (rationals /
floats optional, kept out of the deterministic path). Larger — may land in
slices (reader → eval → closures → builtins). No self-host / cross regression.

## Log
- 2026-06-19 — Opened in the demo-ticket organization pass.
