# `uses X as Y` unit-rename import (dialect extension)

- **Type:** idea
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-06 (from todo.md §4)

## Motivation

A unit-rename import is missing. `uses X as Y` is **not** standard Pascal (that's
C#/Python `as`); Delphi has `uses U in 'file'` + dotted namespaces but no
rename-import. A rename would be a deliberate dialect extension.

## Open questions

- Is the ergonomic win worth a non-standard `uses` form?
- Interaction with qualified `UnitName.Symbol` lookup (already works).
- Syntax: `uses X as Y` vs something less Python-flavored.

## Status

Idea only — decide whether to adopt before scoping. Not standard; no current
source needs it.

## Log
- 2026-06-06 — ticket opened from todo.md §4.
