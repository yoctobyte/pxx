# `read` consumes a whole line like `readln`

- **Type:** bug
- **Status:** done
- **Owner:** Antigravity
- **Opened:** 2026-06-06 (from todo.md §4 / rainy-afternoon)

## Symptom

`read` currently reads a fresh line and discards the remainder, behaving like
`readln`. Separate `read` calls on one input line do not each consume the next
token from that line.

## Expected

`read(a); read(b);` should consume successive values from the **same** input
line, preserving the unread remainder across calls (FPC behavior).

## Scope

- Keep the unread remainder of the current line in the line buffer across `read`
  calls; only `readln` discards to end-of-line.

## Acceptance

`test/test_readln.pas` (or a new test) shows two `read` calls pulling two values
from one line; `readln` still advances past the line.

## Log
- 2026-06-06 — ticket opened from todo.md §4.
- 2026-06-06 — claimed by Antigravity; working on implementation.
- 2026-06-06 — resolved in 52d4ffd; verified by test/test_readln.pas.
