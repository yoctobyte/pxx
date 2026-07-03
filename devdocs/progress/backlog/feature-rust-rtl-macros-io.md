# Rust frontend RTL — `println!`/`format!`/`vec!`/`assert!`/`panic!` runtime

- **Type:** feature — Track B
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-07-03
- **Umbrella:** [[feature-rust-frontend]] — sub-ticket 12/12. Depends on
  [[feature-rust-macro-rules]] (intrinsic recognition, Track A side) and
  [[feature-rust-misc-semantics]] (format-string parser, Track A side).

## What it does

RTL-side bodies backing the builtin-macro intrinsics parsed by
[[feature-rust-macro-rules]]:

- `println!`/`eprintln!`/`format!` — call the format-string parser
  ([[feature-rust-misc-semantics]]) then write to stdout/stderr/build a
  `String`, respectively.
- `vec!` — literal-array-ctor over `Vec<T>` ([[feature-rust-rtl-core-types]]).
- `assert!`/`assert_eq!`/`debug_assert!` — condition check + `panic!` with a
  formatted message on failure.
- `panic!` — formatted message + abort. Per
  [[feature-rust-drop-move-tracking]]'s non-goals: `~/nextlevel`'s
  `Cargo.toml` sets `panic="abort"`, so this maps straight to existing
  `Halt`/exception machinery — no unwind-and-run-Drop-along-the-stack
  behavior needed for that target. A future program that doesn't set
  `panic="abort"` would need real unwinding — explicitly not this ticket.

## Acceptance

- All 6 macros produce correct runtime behavior against the format-string
  and `Vec` sub-tickets once those land.
- `panic!` aborts with the formatted message printed, matching
  `panic="abort"` semantics exactly (no partial unwind, no Drop calls
  during the abort — consistent with the non-goal above).

## Log
- 2026-07-03 — split from [[feature-rust-frontend]] umbrella at ticket-craft
  time. No code written yet.
