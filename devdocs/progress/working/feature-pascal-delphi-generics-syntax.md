---
prio: 56  # auto — 93 conformance tests behind it, second-biggest unlock
---

# Mode-Delphi generics syntax: `TFoo<T> = class`, inline `TFoo<LongInt>`

- **Type:** feature (Pascal frontend, dialect)
- **Track:** P (shared `lexer.inc`/`parser.inc` — A-gated, sole-A confirmation
  before edit)
- **Status:** working
  ([[feature-pascal-corpus-fpc-testsuite]]).
- **Owner:** opus-a

## Symptom
pxx only parses objfpc-style `generic TFoo<T> = class` + `specialize
TFoo<LongInt>`. `{$mode delphi}` code declares `TTest<T> = class ... end;` and
uses `TTest<LongInt>` inline with neither keyword. Errors in the cluster:
`Expected: begin, but got: TTest`, `Expected: :, but got: class/private`.

Related smaller clusters (same area, roll in or split as work reveals):
- inline `specialize` in expression/return-type position (3 tests:
  `error: undefined variable (specialize)`, `base type not found: specialize`)
- generic functions `tgenfunc*` (mode-Delphi generic methods/functions)

## Impact
**93 of 294** curated failures (`tgeneric*`, `tgenfunc*`, `tdefault*`,
`tgenconstraint*` mode-delphi halves). Skip-list reason:
`parser: mode-Delphi generics TFoo<T> syntax`.

## Fix sketch
In mode delphi, on `IDENT <` at a type-declaration or type-reference position,
enter the generic parse path (the `<` vs less-than ambiguity needs the usual
lookahead: only in type context, or expression context followed by type-list +
`>` + `(`/`.`). Reuse the existing generic/specialize machinery — this is a
surface-syntax alias, not a new semantics engine.

## Gate
`make test` + self-host byte-identical; burn the 93 skip-list entries.
