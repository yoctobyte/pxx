# Compiler warning diagnostics facility

- **Type:** feature
- **Status:** done
- **Owner:** —
- **Unblocks:** feature-lazycasing-c-imports
- **Opened:** 2026-06-06 (prerequisite surfaced by lazycasing ticket)

## Motivation

The compiler can emit `{$warning}`/`{$message}`/`{$error}` from source directives,
but has no general facility to raise its **own** warnings for accepted-but-suspect
situations (e.g. a case-insensitive C-import match, a narrowing, an ignored
attribute). Several planned features want to accept something yet make it visible.

## Scope

- A `Warn(...)` path that prints `file:line: warning: ...` without halting.
- Consistent formatting with existing errors; routed to stderr.
- Optional: a switch to promote warnings to errors later (not required now).

## Acceptance

A deliberately suspect construct emits a non-fatal warning with location; the
program still compiles; no regression in error handling. First consumer:
`feature-lazycasing-c-imports`.

## Log
- 2026-06-06 — ticket opened as the warnings prerequisite for lazycasing.
- 2026-06-22 — DONE (Track A), commit a50bbd5. Added `Warn(msg)` / `WarnAt(line, msg)` in
  lexer.inc (next to `Error`): prints `pascal26:<line>: warning: ...`, increments
  `WarnCount`, keeps compiling. `-Werror`/`--werror` (WarnAsError) promotes the
  next warning to a fatal error. Re-routed the existing `{$warning}` directive
  through `WarnAt` so it is counted and honours -Werror. Gate green: self-host
  fixedpoint + threadsafe self-host byte-identical, make test + asm-emit all
  targets OK. First in-tree consumer is the `{$warning}` directive; the C-import
  case-insensitive match (feature-lazycasing-c-imports) is the next consumer.
