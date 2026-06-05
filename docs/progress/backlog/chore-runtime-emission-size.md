# Finer runtime-support emission (code size)

- **Type:** chore
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-06 (from rainy-afternoon)

## Motivation

A coarse Pascal gate already omits unused heap startup and managed-string
helpers (hello: 1,134 → 287 bytes). Finer reachability cleanup remains, relevant
before embedded targets and deeper code-size tuning.

## Scope

Audit: `../../developer/runtime-emission-size-audit-2026-06-02.md`.

- Split helper dependencies so only reached helpers emit.
- Gate argv-stack preservation.

## Acceptance

Measured hello/embedded overhead drops further with no functional regression;
suite green; self-host fixedpoint holds.

## Log
- 2026-06-06 — ticket opened from rainy-afternoon.md.
