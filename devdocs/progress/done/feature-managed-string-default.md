# Promote managed AnsiString from opt-in to default

- **Type:** feature
- **Status:** done
- **Owner:** Codex
- **Blocked-by:** bug-managed-byref-string-param-store, feature-managed-exception-cleanup
- **Opened:** 2026-06-06 (from todo.md §2d / §4)

## Motivation

`AnsiString` now uses the heap-backed, refcounted, copy-on-write representation
by default. The frozen fixed-capacity inline ABI remains available with
`-uPXX_MANAGED_STRING` for compatibility testing.

## Scope

Plan: `../../developer/plan-refcounted-compiler-strings.md`. Delivered:

- `PasInitDefines` seeds `PXX_MANAGED_STRING` by default.
- `make bootstrap` and `make test` use the managed default path.
- `make test-frozen`, `make test-nilpy-frozen`, `make bootstrap-frozen`, and
  `make stabilize-frozen` keep an explicit `-uPXX_MANAGED_STRING` opt-out lane.
- Stale docs and the exact frozen hello-size assertion were updated for the new
  default.

User direction (memory): wants per-use string typing / right-sizing, not a blunt
global flip.

## Acceptance

Managed strings selectable as default with all ownership paths covered; compiler
self-host fixedpoint holds under the managed default; BSS drops accordingly.

## Log
- 2026-06-12 — Done by Codex. `make bootstrap` produced a managed-default
  fixedpoint (`bss=133040256B`, down from the frozen ~1.67 GB scale); `make test`,
  `make test-nilpy`, `make fpc-check`, `make test-frozen`, and `make symbols`
  pass.
- 2026-06-12 — Added benchmark coverage for both Hello World output modes.
  Sanity run: managed-default hello = 24,665 bytes; frozen
  `-uPXX_MANAGED_STRING` hello = 287 bytes.
- 2026-06-12 — Claimed by Codex; starting managed-string default packaging/reseed work.
- 2026-06-06 — ticket opened from todo.md §2d/§4.
