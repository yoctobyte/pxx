---
slug: bug-c-system-libs-objects-import-crtl-only-names
track: C
prio: 70
type: bug
status: done
owner: pxx2
created: 2026-11-27
closed: 2026-11-28
found-by: pxx2 (pxx-built libwlroots linked into gcc-built Panorama, a test setup)
tags: [cfront, crtl, system-libs, wlroots, panorama]
summary: "An --emit-obj --system-libs object is linked against the host libc, but crtl's headers still sent four things to crtl-only names: gcc's bit builtins (__builtin_popcount -> __pxx_builtin_popcount32, refused at compile time), time() (macro onto __crtl_time), and isfinite / signbit (declared as functions; glibc has them only as macros). Now <stdlib.h> carries static copies of the bit-builtin bodies under __PXX_SYSTEM_STDLIB__ (one source, pxx/bitbuiltins.h, shared with stdlib.c), and new predefines __PXX_SYSTEM_TIME__ / __PXX_SYSTEM_MATH__ spell time, finite and __signbit the host's way. Test c_syshost26 (pxx object, gcc main, glibc)."
---

# --system-libs objects imported names no libc exports

Found building wlroots 0.20.2 with `--emit-obj --system-libs --threadsafe`
to link into Panorama (gcc, glibc) as a test setup. Comparing the
objects' undefined symbols with gcc's (scratch undefcmp):

| construct | pxx object needed | glibc has |
|---|---|---|
| `__builtin_popcount` (wlr_data_offer.c) | `__pxx_builtin_popcount32`, refused at compile time | nothing; gcc inlines it |
| `time(NULL)` (xwayland/server.c) | `__crtl_time` (time.h's macro) | `time` |
| `isfinite(x)` (wlr_cursor.c) | `isfinite` | `finite`, `__finite` (isfinite is a macro) |
| `signbit(x)` | `signbit` | `__signbit` |

The pattern already existed for assert, pthread and atexit
(`__PXX_SYSTEM_ASSERT__`, `__PXX_SYSTEM_PTHREAD__`, `__PXX_SYSTEM_STDLIB__`):
the header knows it is on the system-library path and spells the host's names.

- **bit builtins**: the 13 bodies moved from src/stdlib.c into
  `include/pxx/bitbuiltins.h`, defined with a storage-class macro.
  stdlib.c includes it with that macro empty, so crtl's build is unchanged.
  `<stdlib.h>` includes it with `static` under `__PXX_SYSTEM_STDLIB__`: each
  object carries private copies, as gcc's inline expansion would. A unit that
  uses a builtin without `<stdlib.h>` still gets the refusal; wlroots has none.
- **time**: under `__PXX_SYSTEM_TIME__` (cpreproc), `time` is declared plainly.
- **isfinite / signbit**: under `__PXX_SYSTEM_MATH__`, macros onto `finite`
  and `__signbit`.

Remaining extra imports compared with gcc are all real glibc or xcb symbols:
gcc drops unused statics that call `xcb_ewmh_*`, pxx keeps them, and the
`--static --libs` link resolves them.

Test test/c_system_libs_host_names.c + _main.c (row c_syshost26): the pxx
object linked by gcc against glibc, output equal to the gcc build
(`.expected`). It also covers struct stat
(bug-crtl-struct-stat-is-not-glibc-s-layout-on-x86-64). Before the fix:
"__pxx_builtin_popcount64 is a pxx-internal runtime symbol and cannot be
imported dynamically".

Result of the test setup: Panorama's five headless checks (panorama-ae's
list) give the same app content with either libwlroots; only the clock's
seconds differ, and every run exits 0.
