# Promote managed AnsiString from opt-in to default

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Blocked-by:** bug-managed-byref-string-param-store, feature-managed-exception-cleanup
- **Opened:** 2026-06-06 (from todo.md §2d / §4)

## Motivation

`{$define PXX_MANAGED_STRING}` already gives heap-backed, refcounted,
copy-on-write `AnsiString` and reaches managed self-compile fixedpoint. The
default representation is still the fixed-capacity inline buffer (~1.6 GB BSS in
the compiler). Promoting managed to default is a product decision blocked on a
few ownership gaps.

## Scope

Plan: `../../developer/plan-refcounted-compiler-strings.md`. Remaining before a
default flip:

- Globals ownership.
- Exception-path cleanup (see `feature-managed-exception-cleanup`).
- Remaining record/class ownership audits.
- Final default-ABI packaging + seed/reseed decision.

User direction (memory): wants per-use string typing / right-sizing, not a blunt
global flip.

## Acceptance

Managed strings selectable as default with all ownership paths covered; compiler
self-host fixedpoint holds under the managed default; BSS drops accordingly.

## Log
- 2026-06-06 — ticket opened from todo.md §2d/§4.
