# C: lua runner tests regressed (segfault on most scripts)

- **Type:** bug (C frontend / runtime regression) — Track C
- **Status:** done
- **Owner:** Codex
- **Found / Opened:** 2026-06-28, noticed while verifying the crtl auto-pull
  change ([[c-linking-and-crtl-autopull]]).

## Symptom

`make test-lua` fails: of the lua scripts only `oop.lua` passes; `closures.lua`,
`coroutines.lua`, `strings.lua` **segfault** the runner, and `files.lua` /
`numeric.lua` produce wrong output.

## Pre-existing, not the auto-pull change

Confirmed identical failures on the compiler built from `d320278b` (the commit
BEFORE the crtl auto-pull work) — the auto-pull is byte-neutral for lua (no
impl is auto-pulled; `runner.c`'s explicit `#include "*.c"` unity build is
deduped, output binary is identical). So lua regressed at some earlier point.

`test-lua` is **not** part of `make test` (the default gate is `test-core
test-debug-g lib-fpc-clean`), which is why the regression drifted in unnoticed.

## Notes / leads

- Memory records lua as previously FUNCTIONAL (control flow, closures, coroutines,
  metatables, string methods, `table.sort`, pcall) — see the M5 lua bring-up
  notes. So a compiler change between then and now broke it.
- The passing case (`oop.lua`) vs the segfaulting ones (`closures`, `coroutines`,
  `strings`) suggests something in closures / upvalues / coroutine stack / string
  interning — bisect compiler commits against `make test-lua` to localise.
- Consider adding `test-lua` (and a sqlite smoke, once it runs) to the gate so C
  bring-up regressions are caught.

## Acceptance

- `make test-lua` green again (all scripts match expected).
- Root-cause commit identified; regression test added to the standard gate.

## Log

- 2026-06-29: Moved to working. Reproducing `make test-lua` failures and
  reducing the crash/wrong-output cause.
- 2026-06-29: Done. Root cause was C `#if` evaluation expanding object-like
  macros recursively but not function-like macro calls. Lua's
  `L_INTHASBITS(SIZE_Bx)` therefore evaluated false, `MAXARG_Bx` fell back to
  `INT_MAX`, and Lua bytecode immediates decoded as values like `0xC0000002`.
  Added function-like macro expansion in `#if`, restored `make test-lua`, and
  wired reduced Lua-shaped C regressions into `test-core`.
