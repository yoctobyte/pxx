# Rust frontend — lexer/parser skeleton + entry point

- **Type:** feature — Track A
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-07-03
- **Umbrella:** [[feature-rust-frontend]] — sub-ticket 1/12, gates all others.

## What it does

Bring up `rlexer.inc` + `rparser.inc` (new files, same shape as
`clexer.inc`/`cparser.inc`) and a `ParseRustProgram` entry point wired the
same way `ParseCProgram` is: file-extension or explicit-flag dispatch,
lowering straight to the existing shared AST/IR — no new backend, no new
ELF/ABI work.

Scope for the *skeleton* specifically (deliberately small — this ticket is
"can we parse and lower a trivial Rust program," not "support Rust"):

- Lexer: Rust token set (keywords, `::`, `->`, `..`/`..=`, lifetimes as a
  token shape `'a` even though unenforced, raw strings `r"..."` if cheap).
- Parser: `fn`, `let`/`let mut`, plain expressions/binops, `if`/`else`,
  `while`/`loop`, plain (non-generic, non-trait) `struct`, function calls,
  `return`. No `match`, no generics, no traits, no `enum`-with-data, no
  `impl` blocks yet — those are the later sub-tickets.
- Lower directly onto existing AST nodes (`AN_IF`/`AN_WHILE`/`AN_CALL`/etc.)
  — the whole point of this ticket is proving the existing shared AST/IR is
  sufcient for the boring 80% before spending effort on the hard 20%.

## Acceptance

- A trivial multi-function Rust program (arithmetic, `if`/`while`, plain
  structs, no traits/generics/match) parses and self-compiles to correct
  runtime output.
- Existing `make test` unaffected (new frontend, isolated files, no shared
  internals touched beyond the same entry-point-dispatch pattern C uses).
- Ticket stays Track A per the shared-internals rule even though this is
  "a new frontend" — same reasoning as C: shared AST/IR/symtab changes are
  Track A regardless of which frontend triggers them.

## Log
- 2026-07-03 — split from [[feature-rust-frontend]] umbrella at ticket-craft
  time. No code written yet.
