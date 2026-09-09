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

`AN_INTF_CALL` (defs.inc) already dispatches through an interface — but NOT as
the data-ptr + vtable-ptr fat pointer this plan was written against. **An
interface value in pxx is ONE WORD: the instance pointer.** The IMT is
recovered per call from the instance's RTTI by `PXXIntfIMTOf(inst, ifaceId)`,
which is what lets the value stay a single pointer. `AN_INTF_FROM_CLASS`, which
this line also named, was the fat-pointer BUILD node and was retired on
2026-09-09 — it had constructed nothing for months.

That matters for `dyn Trait` and is not a wording fix: the pxx mechanism gets
its method table from the RECEIVER'S IDENTITY, so it needs the receiver to have
one (an RTTI blob reachable from the value). A `dyn Trait` over a plain struct
or a primitive has no such blob, so the reuse is NOT "same shape, generalize the
binding" — it is either give those values an identity, or carry a real fat
pointer for the Rust case alongside the one-word Pascal one. Cost that before
planning against it. The gap: current interfaces assume a class hierarchy
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
- Existing class-based interface dispatch (`AN_INTF_CALL`, one-word values,
  IMT via `PXXIntfIMTOf`) unaffected. Whether this GENERALIZES that binding or
  adds a second one beside it is open — see "What it does": the pxx mechanism
  needs the receiver to carry an identity, and a `dyn Trait` over a primitive
  does not.

## Log
- 2026-07-03 — split from [[feature-rust-frontend]] umbrella at ticket-craft
  time. No code written yet.
