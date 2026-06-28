# Case-sensitive C header lookup mismatch on Linux

- **Type:** bug
- **Status:** backlog
- **Track:** A (compiler frontend)
- **Owner:** —
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
- 2026-06-28 — bug ticket opened.
