# bug: cardinal/signed 32-bit expression width (orphan addendum)

- **Type:** bug (Track A — type promotion / codegen width)
- **Status:** DONE 2026-06-23 (both halves resolved elsewhere)
- **Found:** 2026-06-23, differential probe vs FPC

This file was an orphaned addendum fragment. Both parts are fixed and tracked by
their own done tickets:

1. **Cardinal/LongWord binary-op → uint64 (FPC: int64).** Resolved — see
   `done/bug-cardinal-expr-promotion.md` (TypeArithmeticResult only widens to
   uint64 for a genuinely 64-bit unsigned operand).

2. **Signed 32-bit `shr` widened to 64-bit** (the "## Also" addendum that lived
   here: `Integer(-8) shr 1` gave a 64-bit value). Resolved — see
   `done/bug-shr-signed-integer-width.md` (commit 346a26f: shr at operand width
   on x86-64 + aarch64). Re-verified 2026-06-23 vs FPC `{$mode objfpc}`:
   `i shr 1`, `c shr 1`, `l shr 1`, `i shr 28` all match.

Closed to clear the backlog stub; no remaining work.
