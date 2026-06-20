# feature-compiler-search-path-pcl (Track A)

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-20

## Description

The GUI library has been renamed from Lazarus Component Library (LCL) to Pxx Component Library (PCL) to avoid naming confusion with Lazarus. The library units under `lib/` have been relocated from `lib/lcl/` to `lib/pcl/`.

Currently, the compiler has hardcoded paths to search `lib/lcl/` for fallback library units (specifically in `compiler/parser.inc` around lines 9518, 9525, 9604, 9607). These should be updated to search `lib/pcl/` instead of `lib/lcl/`.

## Affected Files in Compiler

In `compiler/parser.inc`:
- Line 9518: Update default `lcldir` fallback path string from `'lib/lcl/'` to `'lib/pcl/'`.
- Line 9525: Update `lcldir` assembly logic from `'../lib/lcl/'` to `'../lib/pcl/'`.
- Lines 9604, 9607: Update CWD-relative search fallbacks from `'lib/lcl/'` to `'lib/pcl/'`.

## Done Criteria

- The compiler uses `lib/pcl/` as the default directory for PCL/GUI units instead of `lib/lcl/`.
- Building a GUI program (e.g. `test/gui/test_pcl_window.pas`) compiles successfully without needing explicit `-Fulib/pcl/` search flags, using default compiler resolution.

## Log
- 2026-06-20 — Opened during Track B renaming of LCL to PCL.
