---
prio: 45  # auto
---

# Rust frontend — integer overflow mode + format-string parser

- **Type:** feature — Track A
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-07-03
- **Umbrella:** [[feature-rust-frontend]] — sub-ticket 9/12. Depends on
  [[feature-rust-frontend-skeleton]]. Bundled together as two small,
  self-contained, independently-testable pieces — not because they're
  related in concept.

## What it does

**1. Integer overflow mode.** Rust panics on integer overflow in debug
builds, wraps in release. PXX currently just wraps everywhere (like C). Add
a mode flag, same pattern as the existing `--no-div-check` opt-out
(see [[project_div_zero_re200_v135]] for the precedent this mirrors): a
pre-op overflow check that raises/panics when the mode is on, no-ops (plain
wrap, current behavior) when off. Cheap — one flag, one check site pattern
already proven for div-by-zero.

**2. Format-string mini-parser.** `println!("{} {:?}", a, b)` needs a real
format-spec parser: `{}` (Display), `{:?}` (Debug), positional/named args,
width/precision/fill specifiers. Self-contained, bounded scope — nobody's
designed this yet in this codebase. Feeds:
- [[feature-rust-rtl-macros-io]] (the `println!`/`format!` intrinsics)
- [[feature-rust-derive-macros]]'s `Debug` derive (needs to produce
  `{:?}`-compatible output)

## Scope

- Format parser: cover `{}`, `{:?}`, positional (`{0}`), named (`{name}`),
  and the common width/precision/fill subset. Skip exotic specifiers
  (`{:#x}`-style alternate hex, `{:+}` sign-forcing) unless real usage
  demands them later — don't build for hypothetical format strings.
- Overflow mode: default matches Rust's own convention (panic in
  debug-equivalent build, wrap in release-equivalent) — tie to whatever
  PXX's existing debug/release distinction is (or add one if none exists
  yet at the flag level).

## Acceptance

- `{}`/`{:?}`/positional/named/width/precision all format correctly against
  a small corpus of derived-`Debug` and `Display`-able types.
- Overflow mode: an `Int32` add past `MAX_INT` panics when mode is on,
  wraps identically to current behavior when off; zero behavior change to
  existing Pascal/C code (opt-in flag, not a default-on change to shared
  codegen).

## Log
- 2026-07-09 — the format-string half landed on master (ports-back pass,
  commit bbd15a52): `{}`/`{:...}` placeholder splitting behind
  println!/print!, lowered onto AN_WRITE/AN_WRITELN (the Zig frontend's
  splitter shape). `{{ }}` escapes and the integer-overflow mode remain
  open.

- 2026-07-03 — split from [[feature-rust-frontend]] umbrella at ticket-craft
  time. No code written yet.
