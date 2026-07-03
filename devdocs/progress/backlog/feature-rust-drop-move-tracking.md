# Rust frontend — Drop-on-scope-exit + move tracking

- **Type:** feature — Track A
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-07-03
- **Umbrella:** [[feature-rust-frontend]] — sub-ticket 5/12. Depends on
  [[feature-rust-frontend-skeleton]]. **Correctness-critical — read before
  touching.**

## What it does

Two coupled mechanisms Rust's ownership model needs that PXX has no general
form of today:

1. **Scope-exit destructor insertion.** Class dtors currently only run via
   explicit `.Free`; built-in managed types (AnsiString/dynarray) get
   compiler-inserted ARC release. Nothing walks arbitrary stack locals in
   reverse declaration order and calls a user-defined destructor
   (`impl Drop for T`) at block exit — including early `return`/`break`/
   `continue` that cross the scope. Confirmed load-bearing, not
   hypothetical: `~/nextlevel/engine/src/search.rs:252` has a real
   `impl Drop for WorkerThread`.
2. **Move tracking.** Pascal has no concept of "this variable's value was
   moved out and is now invalid." Need a moved-flag per local (symtab-level),
   set when a value is moved (assigned elsewhere, passed by value to a
   function taking ownership), checked so the Drop-insertion pass above
   skips already-moved locals (no double-free) and so a later read of a
   moved-from binding is a compile error (matches Rust's own semantics —
   free correctness win, not extra work).

## Why this is the one to get right first try

Every native RAII compiler (C++, Swift, Rust itself) treats this as
permanent, load-bearing machinery. A mistake here isn't a compile error —
it's a silent double-free or use-after-free in the *output binary*, the
exact class of bug this whole ownership model exists to prevent. Land with
a stress-test corpus (nested scopes, early return, loop `break`/`continue`,
moved-into-closure, moved-into-function-arg) before calling it done, per
[[feedback_verify_claims_before_accepting]] (write regression tests before
declaring fixed — applies doubly here).

## Non-goals

- No panic-unwind-drop-order guarantee. `~/nextlevel`'s own `Cargo.toml`
  sets `panic = "abort"` — panics can map straight to `Halt`, no
  unwind-safe-Drop interaction needed for that app. Don't generalize this
  simplification to programs that don't opt into `panic="abort"`.
- No compile-time proof that a moved-from read is *impossible* in every
  branch (that's borrow-checker territory, explicitly out of scope per
  [[feature-rust-frontend]]) — a runtime/flow-local check catching the
  straight-line cases is the bar.

## Acceptance

- `impl Drop for T` runs exactly once per value's actual scope exit,
  correct order (reverse decl), across early return/break/continue.
- Move-out of a local marks it dead; Drop-insertion skips dead locals;
  no double-free in a stress corpus.
- Read of a moved-from local is a compile error, not silent garbage.

## Log
- 2026-07-03 — split from [[feature-rust-frontend]] umbrella at ticket-craft
  time. No code written yet.
