# `flexcolumn` calling-convention directive

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-06 (from todo.md §4)

## Motivation

The `value:w:d` formatting micro-grammar is today special-cased in
`write`/`writeln`/`Str`. Generalize it into a declarable calling-convention
directive so formatted routines can be ordinary library functions whose call
args carry optional `:w:d` modifiers. Pays off when variadic `write`/`writeln`
move to library code (see `feature-writeln-as-library`).

## Scope

- A declarable directive marking a routine as accepting per-arg `:w:d` modifiers.
- Spec the per-arg modifier → formal mapping and variadic interplay.
- Resolve in the **parser** (it knows the callee's directive) — never the lexer.

Rationale: `plan-pascal-syntax-issues.md` §B1.

## Acceptance

A library `write`-like routine declared with the directive accepts `x:w:d` call
syntax and formats correctly; existing `write`/`writeln`/`Str` unchanged.

## Log
- 2026-06-06 — ticket opened from todo.md §4.
- 2026-06-28 — Removed `chore-inc-to-units` as a blocker after that refactor was
  rejected. This feature remains optional and should justify itself through a
  future library-backed formatted-output path, not through a broad compiler-file
  split.
