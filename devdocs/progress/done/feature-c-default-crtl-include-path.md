# C: auto-search pxx's crtl headers by default (+ `-nostdinc`)

- **Type:** feature (C frontend / include resolution) — Track A/C
- **Status:** done
- **Owner:** —
- **Opened / Closed:** 2026-06-27 (M5 sqlite bring-up,
  [[feature-c-desktop-lua-sqlite-path]]).

## Problem

pxx searched only user `-I` roots for `<>` C includes, then fell back to
`/usr/include`. So `#include <stdarg.h>` resolved to the **host** header (wrong
ABI, doesn't map to pxx's `__builtin_va_*`) unless the caller manually passed
`-Ilib/crtl/include`. That bit the sqlite bring-up (a false "invalid symbol in
lea") and is a reproducibility footgun — real C programs need pxx's own
freestanding/hosted headers on the default path, like any C compiler.

No new language *builtin* was needed — `__builtin_va_arg`/`va_start`/`va_end`
already exist. The gap was purely the default include **search path**.

## What changed

- `AddDefaultCIncludeDirs` (cpreproc.inc): for `.c` inputs, auto-registers
  `lib/crtl/include` as a default `<>` root — both **ExeDir-anchored**
  (`<exedir>/../lib/crtl/include`, robust to CWD; ExeDir = `<root>/compiler/`)
  and **CWD-relative** (`lib/crtl/include/`), mirroring the Pascal PAL-dir
  auto-add. Appended **after** user `-I`, so `-I` still wins (gcc semantics).
- `-nostdinc` / `--nostdinc` (`NoStdInc`): suppresses both the crtl default and
  the `/usr/include` host fallback — for freestanding/ESP/bare or pure builds
  (the canonical gcc flag name).
- The `/usr/include` fallback (cpreproc.inc) is now also gated by `not NoStdInc`.

## Result

- `test/cvarargs_int_b49.c` and sqlite compile **without** the manual
  `-Ilib/crtl/include`. sqlite now reaches its next real wall
  (`xAltLocaltime` function-pointer struct field) on a bare invocation.
- `-nostdinc` correctly makes `<stdarg.h>` unresolved.
- The Makefile's explicit `-Ilib/crtl/include` on C tests is now redundant
  (harmless; left in place).

## Future (noted, not built)

Tier the headers: *freestanding* (`stdarg/stddef/stdint/stdbool/limits/float`)
always on; *hosted* (`stdio/stdlib/string`) only in hosted mode — matters for
ESP/bare. One dir auto-added is enough for the desktop sqlite/lua path now.

## Log

- 2026-06-27 - Implemented default crtl `<>` search + `-nostdinc`; gated
  (self-host byte-identical) and committed. User: "no external libraries needed"
  — pxx ships its own headers; the /usr fallback stays only as a last resort and
  is off under -nostdinc.
