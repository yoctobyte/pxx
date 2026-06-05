# Metaclass alias descendant-constraint enforcement

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-06 (from todo.md §4 / rainy-afternoon)

## Motivation

Named `class of` metaclass aliases are pointer-backed and work for the covered
subset, but do not yet enforce every descendant constraint against arbitrary
pointer-compatible assignments — a too-broad assignment is currently accepted.

## Scope

- Enforce that a value assigned to a `class of TBase` metaclass is `TBase` or a
  descendant; reject unrelated pointer-compatible assignments.

## Acceptance

A test assigning a non-descendant class reference to a metaclass variable is
rejected; valid descendant assignments still compile; self-host fixedpoint holds.

## Log
- 2026-06-06 — ticket opened from todo.md §4.
