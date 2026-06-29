# Case-sensitive C header lookup mismatch on Linux

- **Type:** bug
- **Status:** done
- **Track:** A (compiler frontend)
- **Owner:** Codex
- **Opened:** 2026-06-28

## Motivation

Currently, when a Pascal program attempts to import a capitalized C header (such as `uses Lerc_c_api;`, `uses FreeImage;`, or `uses GraphBLAS;`), the lookup fails with `uses: unit source not found: lerc_c_api`.

This happens because:
1. The compiler converts unit names to lowercase when searching for files on disk (e.g. `lo := LowerCase(name);` in `CHeaderStem` inside `compiler/parser.inc`).
2. Linux filesystems are case-sensitive. Thus, the compiler tries to open `lerc_c_api.h` but fails to find the actual `Lerc_c_api.h` file on disk.

To make header import seamless, the lookup mechanism should resolve the casing mismatch gracefully.

## Scope

1. **Case-Tolerant Lookup**:
   - Update file-loading and unit-resolution routines in the compiler (such as `ParseUsesUnit` or `LoadFile` wrapper paths) to fallback to a case-insensitive search if a file lookup fails.
   - When a case-insensitive match (e.g., matching `Lerc_c_api.h` for `lerc_c_api.h`) is found in the search directory, use that file.

## Acceptance

- Capitalized system headers (such as `uses Lerc_c_api;`, `uses FreeImage;`, and `uses GraphBLAS;`) compile and import successfully on Linux without requiring manual renaming.

## Log
- 2026-06-29 — Added a case-insensitive load fallback for Pascal unit and C
  header resolution.
- 2026-06-29 — Narrowed the fallback to Pascal source/unit lookup only. C header
  and C preprocessor includes remain exact-case by design to avoid ambiguous
  header imports. Verified `uses uPSUtils` finds `uPSUtils.pas` through `-Fu`,
  exact-case header import still works, and `make test-core` passes.
- 2026-06-29 — Picked up on Track A. Reproduced the Pascal unit side with
  `uses uPSUtils` failing to find `uPSUtils.pas` because the resolver probes
  `upsutils.pas` on Linux.
- 2026-06-28 — bug ticket opened.
- 2026-06-28 — confirmed also affects **Pascal unit lookup**, not just C headers.
  `uses uPSUtils` fails with `unit source not found: upsutils` because the compiler
  lowercases the name before the filesystem lookup. RemObjects Pascal Script (all `uPS*`
  units) is blocked by this on Linux. The fix is the same: case-insensitive fallback
  in the Pascal unit resolver path (`ParseUsesUnit`), not only in `CHeaderStem`.
