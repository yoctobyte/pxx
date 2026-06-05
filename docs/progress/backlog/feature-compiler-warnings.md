# Compiler warning diagnostics facility

- **Type:** feature
- **Status:** backlog
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
