# Finalize managed values on exception unwind

- **Type:** feature
- **Status:** done
- **Owner:** Codex
- **Unblocks:** feature-managed-string-default
- **Opened:** 2026-06-06 (from todo.md §2d/§4 + rainy-afternoon)

## Motivation

Managed locals (refcounted `AnsiString`, dynamic arrays) are finalized on normal
scope exit, but **not** on the exception unwind path. Leaks/incorrect refcounts
when an exception crosses a scope holding managed values. Blocks making managed
strings the default.

## Scope

- Emit unwind-path finalization for managed locals and dynamic arrays when an
  exception leaves their scope (mirror the normal scope-exit cleanup).
- Cover record/class fields holding managed values.

## Acceptance

A test that raises through a scope owning managed strings/arrays shows correct
release (no leak, no double-free); self-host fixedpoint holds.

## Log
- 2026-06-12 — Done in commit f2889d0. Regression: `test/test_managed_exception_cleanup.pas`; verified with `make bootstrap`, `make test`, `make test-nilpy`, and `make fpc-check`.
- 2026-06-12 — Claimed by Codex; starting unwind-path managed cleanup work.
- 2026-06-06 — ticket opened from todo.md §2d/§4.
