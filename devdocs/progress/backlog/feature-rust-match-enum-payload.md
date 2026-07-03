# Rust frontend — `match` pattern-bind + generalized tagged union

- **Type:** feature — Track A
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-07-03
- **Umbrella:** [[feature-rust-frontend]] — sub-ticket 2/12. Depends on
  [[feature-rust-frontend-skeleton]].

## What it does

Two coupled gaps, landed together because pattern-bind is meaningless
without a payload to bind against:

1. **Generalized tagged union type.** `tyVariant` (defs.inc ~625) is a fixed
   8-byte-tag + 8-byte-payload slot — fine for `Option<Box<T>>` (pointer-sized
   payload), wrong for any struct/array/multi-field payload variant (the
   common case: `Result<T, E>` where `T` is a real struct). Needs a real
   variable-size tagged union type: discriminant + largest-variant-sized
   payload region, alignment computed like a record.
2. **`match` with destructuring bind.** `AN_CASE` (defs.inc:124) is
   const-selector-only — Pascal `case` never binds names. `match Some(x) =>`
   needs a new AST node that, per arm, extracts the payload and introduces
   `x` as a fresh scoped local for that arm's body only.

## Why this order

Real-world usage confirms this is high-frequency, not a corner case:
`~/nextlevel/engine` alone has 49 `match` sites in 6.1k LOC. `shakmaty`'s
`Move`/`Square`/`Role` enums are struct-payload variants — anything touching
that crate's shape needs the general union, not `tyVariant`.

## Acceptance

- `enum` with struct/tuple-payload variants compiles, sized/aligned
  correctly.
- `match` on such an enum: each arm's bound names are scoped to that arm only,
  read/write correctly, no leakage across arms.
- No exhaustiveness checking required (accepted non-goal — same category as
  skipping the borrow checker: compiles, doesn't reject incomplete matches).
- Regression corpus: nested payload (`Option<MyStruct>`), multi-arm bind,
  arm using bound field by value and by ref.

## Log
- 2026-07-03 — split from [[feature-rust-frontend]] umbrella at ticket-craft
  time. No code written yet.
