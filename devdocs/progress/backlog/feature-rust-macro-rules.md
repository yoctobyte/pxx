# Rust frontend — `macro_rules!` (scope-cut: builtins first)

- **Type:** feature — Track A
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-07-03
- **Umbrella:** [[feature-rust-frontend]] — sub-ticket 7/12. Depends on
  [[feature-rust-frontend-skeleton]].

## What it does

`macro_rules!` is genuinely new machinery vs. C's textual `cpreproc.inc` —
it matches *token trees*, supports repetition (`$()*`), fragment specifiers
(`expr`/`ident`/`ty`/...), and identifier hygiene. Not a reuse of the C
preprocessor.

**v1 scope cut (per [[feature-rust-frontend]] non-goals):** hardcode the
common builtin macros as compiler intrinsics rather than building a general
`macro_rules!` engine:

- `println!`/`eprintln!`/`format!` — wired to
  [[feature-rust-misc-semantics]]'s format-string parser (see
  [[feature-rust-rtl-macros-io]] for the RTL side).
- `vec!` — literal array-ctor sugar over `Vec<T>`
  ([[feature-rust-rtl-core-types]]).
- `assert!`/`assert_eq!`/`debug_assert!` — condition-check + `panic!`.
- `panic!` — formatted message + abort (see
  [[feature-rust-drop-move-tracking]]'s non-goals re: `panic="abort"`).

General `macro_rules!` (arbitrary user-defined macros) is deferred
indefinitely — same call as skipping full borrow-check enforcement: a real
gap, documented, not silently pretended away.

## Acceptance

- The 5-6 builtin macros above work as intrinsics in the parser (recognized
  by name, arg-parsed per their known shape, not general macro expansion).
- A user-defined `macro_rules! foo { ... }` produces a clear "not supported"
  compile error, not a silent misparse.

## Log
- 2026-07-03 — split from [[feature-rust-frontend]] umbrella at ticket-craft
  time. No code written yet.
