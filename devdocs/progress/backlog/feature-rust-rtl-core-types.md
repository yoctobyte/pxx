# Rust frontend RTL — `Option<T>` / `Result<T,E>` / `Box<T>` / `Vec<T>`

- **Type:** feature — Track B
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-07-03
- **Umbrella:** [[feature-rust-frontend]] — sub-ticket 10/12. Depends on
  [[feature-rust-match-enum-payload]] (tagged union, for `Option`/`Result`)
  and [[feature-rust-generics-trait-bounds]] (generic specialization).

## What it does

Four RTL types, all thin wrappers over machinery Track A already provides
once its sub-tickets land — no new compiler primitives, just `lib/rtl`
surface:

- `Option<T>`/`Result<T,E>` — RTL-level generic over the new tagged-union
  type ([[feature-rust-match-enum-payload]]).
- `Box<T>` — thin wrapper over existing heap alloc, single-owner (no
  refcount — `Drop` from [[feature-rust-drop-move-tracking]] handles the
  free, not a counter).
- `Vec<T>` — maps directly onto existing dynarray + generic specialization;
  RTL wrapper supplies the `.push`/`.pop`/`.len`/iterator API surface Rust
  code expects.

## Acceptance

- `Option<T>`/`Result<T,E>` round-trip through `match` correctly (depends
  on the match sub-ticket landing first).
- `Box<T>` allocates/frees exactly once per real ownership lifetime, no
  leak, no double-free (stress-test alongside
  [[feature-rust-drop-move-tracking]]'s corpus).
- `Vec<T>` push/pop/index/iterate match Rust's observable semantics
  (growth need not match Rust's exact capacity-doubling curve — only
  correctness, not the exact reallocation schedule, is the bar).

## Log
- 2026-07-03 — split from [[feature-rust-frontend]] umbrella at ticket-craft
  time. No code written yet.
