# Target-independent layout RTTI (Tier B)

- **Type:** feature
- **Status:** done
- **Owner:** Antigravity
- **Blocked-by:** feature-cross-bootstrap
- **Unblocks:** feature-target-arm32, feature-target-i386
- **Found / Opened:** 2026-06-11

## Description
Replace target-specific assembly-code walkers (for managed record retain/release, nested dynamic array release, and copy-on-write dynamic array cloning) with a generic, relative offset-based layout table (RTTI) traversed by target-independent runtime helpers in `builtinheap.pas`. This allows managed records and dynamic arrays to work across all target architectures (like i386, ARM32, AArch64) without requiring architecture-specific codegen emitters.

## Log
- 2026-06-11 — Tier B layout RTTI completed. Added runtime helpers (`PXXRecordRetain`, `PXXRecordRelease`, `PXXDynArrayRelease`, `PXXDynArrayUnique`) in `builtinheap.pas`. Added RTTI compiler emission in `rtti_emit.inc` and resolved references dynamically in `ir_codegen.inc` to avoid link-time resolution failures for local variables. Fixed System V ABI register-clobbering bug in `SetLength` loops and fixed dynamic array field RTTI count mapping. All tests compiled, self-bootstrapped, and verified successfully.
- 2026-06-11 — Validation pass: `git diff --check`, focused dynamic-array/managed-record tests, `make test`, and `make test-nilpy` all pass. Follow-up race condition filed as `bug-threadsafe-layout-rtti-helper-races`. Commit: 58e3803.
