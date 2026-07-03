# Rust frontend — derive-macro codegen

- **Type:** feature — Track A
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-07-03
- **Umbrella:** [[feature-rust-frontend]] — sub-ticket 6/12. Depends on
  [[feature-rust-frontend-skeleton]].

## What it does

`#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]` synthesizes trait
impl bodies mechanically from a struct/enum's field list — not
`macro_rules!` (no token-tree matching/hygiene needed), just
compiler-generated code walking fields:

- `Clone`/`Copy` — field-wise copy (bitwise for `Copy`, recursive
  `.clone()` calls for `Clone`).
- `Debug` — field-wise formatted-string builder (depends on
  [[feature-rust-misc-semantics]]'s format-string parser for the `{:?}`
  path other code uses to print it, but the derive itself just needs to
  emit a "TypeName { field: value, ... }" builder).
- `Default` — field-wise `Default::default()` construction.
- `PartialEq`/`Eq` — field-wise `==` chain.

Real-world confirmation: `~/nextlevel/engine` uses these 10x across 6.1k
LOC — common, not exotic.

## Acceptance

- Each of the 5 derives above, on both plain structs and payload-enum
  variants (depends on [[feature-rust-match-enum-payload]] for the enum
  case), produces a correct impl callable the same way a hand-written one
  would be.
- Nested derive (a struct containing a field whose type also derives the
  same trait) composes correctly (recursive call, not inlined field access).

## Log
- 2026-07-03 — split from [[feature-rust-frontend]] umbrella at ticket-craft
  time. No code written yet.
