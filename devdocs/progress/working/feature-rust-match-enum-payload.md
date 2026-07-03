# Rust frontend — `match` pattern-bind + generalized tagged union

- **Type:** feature — Track A (Track R)
- **Status:** working
- **Owner:** Claude (~/frank2, branch `feature/rust-frontend-skeleton`)
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
- 2026-07-03 — landed, with a scope-narrowed design that needed **no new
  `TTypeKind` and no new shared AST node** (so: no Track A hand-off ticket —
  everything below lives in `compiler/rparser.inc` only):
  - **Tagged union, reusing `UClass`.** An enum is a `UClass` (flagged via
    a new Rust-frontend-private `REnumCi` array) whose fields are a
    synthetic `__tag: i64` at offset 0, then every variant's payload fields
    registered at the *same* overlapping offset 8 with variant-qualified
    mangled names (`"Circle.0"`, `"Rectangle.width"`). `AddUField`/
    `FindUField`/`RecFieldType` never assumed disjoint offsets — they just
    do a name lookup in a class's field window — so this is a real union
    via 100% existing machinery.
  - **`match`, desugared at parse time.** No `AN_MATCH` node: each arm
    compiles to an `AN_IF` comparing `__tag`, folded right-to-left into a
    nested if/else chain; bound names are ordinary fresh `AllocVar` locals
    assigned from the mangled field before the arm body is parsed.
  - Enum construction is `let`-only (`let x = Variant(...)`, `let x =
    Enum::Variant { .. }`), same restriction plain struct literals already
    have — no AST node represents "a whole struct/union value" as a
    subexpression yet.
  - Found and fixed one real bug during testing: binding a struct-payload
    field (`Box(rect: Rectangle)`) didn't set `LastTypeRecId` before
    `AllocVar`, so the bound local's `RecName` was wrong and field access
    on it silently read the wrong bytes instead of erroring — fixed by
    calling `RecFieldRecId` alongside `RecFieldType` at both bind sites.
  - Verified: unit/tuple/struct-payload variants, a struct-typed payload
    nested inside a variant (stand-in for the ticket's `Option<MyStruct>`
    example — true `Option<T>` needs generics, sub-ticket 3, and the RTL,
    sub-ticket 10, both after this one in the umbrella's own order),
    wildcard `_` arm, qualified `Enum::Variant` construction/matching, and
    two arms binding the *same* name in one `match` resolving independently
    (no cross-arm leakage). `make bootstrap` self-host stays byte-identical;
    `make -k test` green except the same pre-existing environment failure
    noted in sub-ticket 1 (confirmed unrelated).
  - Known, documented (not silently dropped) narrowing: match scrutinee
    must be a plain local variable, not an arbitrary expression; bare
    variant names must be unique program-wide or use `Enum::Variant`; a
    match-arm binding does not roll back the symbol table, so (consistent
    with this compiler having no block scoping anywhere else) a name reused
    by code *after* the whole match statement could be shadowed by a
    leftover arm binding.
  Next: sub-ticket 3, [[feature-rust-generics-trait-bounds]].
- 2026-07-03 — **correction**: same caveat as sub-ticket 1's log —
  correctness verified against the FPC-built compiler, not the self-hosted
  one; see [[bug-selfhost-multifn-ifelse-miscompile]] (filed urgent, Track
  A, not caused by this frontend). t2.rs/t3.rs in this ticket's own
  verification also have 3+ user functions and would very likely reproduce
  that bug too if run through a fresh `make bootstrap` binary — re-check
  once the bug ticket lands a fix.
