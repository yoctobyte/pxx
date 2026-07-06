---
prio: 45  # auto
---

# Rust frontend — `dyn Trait` dispatch for arbitrary types

- **Type:** feature — Track A
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-07-03
- **Umbrella:** [[feature-rust-frontend]] — sub-ticket 4/12. Depends on
  [[feature-rust-frontend-skeleton]].

## What it does

`AN_INTF_FROM_CLASS`/`AN_INTF_CALL` (defs.inc ~186-189) already build a
data-ptr + vtable-ptr fat pointer for interface dispatch — same shape
`dyn Trait` needs. The gap: current interfaces assume a class hierarchy
underneath (COM/CORBA-style — only classes implement interfaces). Rust
`dyn Trait` can wrap *any* type: structs, primitives, no inheritance
required.

Needs a trait-impl table keyed by `(concrete type, trait)` independent of
class hierarchy, so `impl Display for MyStruct` (a plain struct, not a
class) can still produce a `dyn Display` fat pointer.

## Scope

- Reuse the fat-pointer representation as-is (data ptr + vtable ptr) —
  only the *lookup*/binding model changes, not the runtime shape.
- `shakmaty-syzygy` uses `dyn` 20x in 4k LOC — confirms this isn't a rare
  path if/when dependency source is ever tackled, though v1 scope
  (per umbrella) is app code only.

## Acceptance

- `impl Trait for PlainStruct` (no class involved) produces a working
  `dyn Trait` value; virtual call through it dispatches to the right impl.
- Existing class-based interface dispatch (`AN_INTF_FROM_CLASS` current
  callers) unaffected — this generalizes the binding, doesn't replace it.

## Log
- 2026-07-03 — split from [[feature-rust-frontend]] umbrella at ticket-craft
  time. No code written yet.
