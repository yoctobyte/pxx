# Enforce private/protected visibility

- **Type:** idea
- **Status:** rainy-day 
- **Owner:** —
- **Opened:** 2026-06-06 (from todo.md / limitations)

## Motivation

Class visibility sections (`private`/`protected`/`public`/`published`) are parsed
because `published` drives RTTI, but private/protected access is **not enforced**.
Enforcing it enables no new programs, so it is intentionally deferred until
compatibility pressure justifies it.

## Scope (if adopted)

- Reject out-of-scope access to `private`/`protected` members.
- Keep `published`/RTTI behavior unchanged.
- Decide whether strict-mode-only or always-on.

## Status

Idea / parked. Adopt only when real source fails to compile elsewhere because we
don't enforce this.

## Log
- 2026-06-06 — ticket opened from limitations/todo.
