# `flexcolumn` calling-convention directive

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Blocked-by:** chore-inc-to-units
- **Opened:** 2026-06-06 (from todo.md §4)

## Motivation

The `value:w:d` formatting micro-grammar is today special-cased in
`write`/`writeln`/`Str`. Generalize it into a declarable calling-convention
directive so formatted routines can be ordinary library functions whose call
args carry optional `:w:d` modifiers. Pays off when variadic `write`/`writeln`
move to library code (see `chore-inc-to-units`).

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
