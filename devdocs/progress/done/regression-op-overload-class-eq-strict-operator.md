---
prio: 50
track: A
resolved: 693b4da4
---

# regression: test_op_overload.pas red — b369 made class = / <> rejection unconditional

- **Type:** regression (borg STILL-RED test-core#test_op_overload.pas@1/@2,
  bisected bad `0b873006a9a1` last good `1d489ff4aee6`, 1 commit).
- **Resolved:** 693b4da4, 2026-07-14.

## Root cause

b369 (burn the last %FAIL diagnostics) added the toperator71 FPC-parity
rejection — `operator =` / `<>` on class operands — UNCONDITIONALLY. The PXX
dialect deliberately allows value-equality operators on classes;
test_op_overload.pas exercises exactly that. Policy: FPC-parity strictness
lives behind per-feature strict flags; sweep runs with them on.

## Fix

- Rejection now gated on new `StrictOperator` (`--strict-operator` /
  `{$STRICT_OPERATOR ON}`), plumbed like StrictCase.
- NOT on `--strict-overload`: sweeping with that flag failed 16 conformance
  tests — FPC itself accepts shadowing system functions (`Hi`) without an
  `overload` directive, so that flag can't join the sweep flags.
- `tools/run_pascal_conformance.sh` CCFLAGS: `--strict-case --strict-operator`.
- The sibling b369 rejection (duplicate conversion operator, toperator92/95)
  stays unconditional — silent ambiguity, no dialect use case.

## Gate
Sweep 293/0 (toperator71 still %FAIL-rejected); lax test_op_overload compiles
and runs; quick green; self-host fixedpoint byte-identical; FPC canary green.
