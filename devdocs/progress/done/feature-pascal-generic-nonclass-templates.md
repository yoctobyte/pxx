---
prio: 50  # auto — 10 conformance tests
---

# Generic templates beyond classes: records, arrays, procvars

- **Type:** feature (Pascal frontend, generics)
- **Track:** P (shared `parser.inc` — A-gated)
- **Status:** done
  ([[feature-pascal-corpus-fpc-testsuite]]).
- **Owner:** opus-p

## Symptom
`error: generic templates must be class declarations` — pxx only allows
`generic T<...> = class`. FPC also allows generic **records** (`generic
TRec<T> = record`), **dynamic arrays** (`generic TArr<T> = array of T`), and
**procedure types**.

## Impact
10 curated failures. Skip-list reason: `parser: generic record/array/procvar
templates`.

## Gate
`make test` + self-host byte-identical; burn the skip-list entries.

## Log
- 2026-07-12 — resolved, commit HEAD.
