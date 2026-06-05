# `{$LAZYCASING ON/OFF}` for C imports only

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Blocked-by:** feature-compiler-warnings
- **Opened:** 2026-06-06 (from todo.md §4)

## Motivation

Compatibility convenience for imported C APIs: after an exact-case lookup fails,
allow a case-insensitive fallback **only** for C-imported symbols, and only when
exactly one matches. A convenience for imported APIs, not a Pascal mode.

## Scope

- New `{$LAZYCASING ON/OFF}` switch, **default off**.
- Fallback applies to C-import symbols only; ambiguous matches rejected.
- Preserve each declaration's exact spelling for ELF linkage.
- Must NOT weaken `{$CASESENSITIVE ON}` Pascal code.
- **Prerequisite:** warnings support, so accepted spelling mistakes are visible.

## Acceptance

A C-import call with wrong case resolves under `{$LAZYCASING ON}` (single match),
emits a warning, links to the exact symbol; ambiguous case errors; Pascal
case rules unaffected.

## Log
- 2026-06-06 — ticket opened from todo.md §4.
