---
track: C
tags: [c, crtl, system-libs, rump, netbsd]
prio: 30
type: bug
blocked-by: []
summary: "Under --system-libs, `assert()` from crtl's <assert.h> called __pxx_assert_fail, whose body (crtl src/assert.c) is not pulled on that path and which no libc exports. The build was refused by the __pxx_* import guard (NetBSD rumpuser sp.c and bio.c). It now binds to the libc's own __assert_fail."
status: done
owner: claude-dupwt
---

# assert() under --system-libs imported __pxx_assert_fail

Found in the rump re-measure after row 1
([[feature-c-inline-asm-x87-and-system-instructions]]): rumpuser's `sp.c` and
`bio.c` are built `--freestanding --system-libs`, include `<assert.h>`, and
were refused with "__pxx_assert_fail is a pxx-internal runtime symbol and
cannot be imported dynamically".

## Cause

crtl's header is used on every path, but its impl is pulled only when the
header is NOT on the system-library path (`CHeaderUsesSystemLib`). The header
named crtl's sink unconditionally. This is the same shape as stdarg's
`__pxx_va_*` (bug-c-builtin-va-list-needs-stdarg). stdarg is compiler support
and is always pulled. assert is library, so the right sink on the system path
is the libc's own.

## Fix

The preprocessor predefines `__PXX_SYSTEM_ASSERT__` when `assert` is on the
system-library path, and `<assert.h>` then declares and calls
`__assert_fail(expr, file, line, func)`, the glibc and musl ABI.
`test/c_assert_system_libs.c` builds with `--system-libs` and links to
libc's `__assert_fail` (checked with nm: `U __assert_fail`).

## Seen while fixing, not fixed here

- **crtl's pthread types are not glibc's layout** (mutex 24 bytes against
  glibc's 40, cond 4 against 48, attr 4 against 56). Yet under --system-libs
  `pthread_mutex_lock` and friends bind to glibc, and only pthread_create and
  pthread_join are renamed to crtl's `__pxx_crtl_*`. That rename is the next
  error in rumpuser bio.c. Handed to the crtl owner (rump row 5).
- `--system-libs=c` alone (no bare flag) stops at "the entry stub asked for
  a pre-main initializer phase but __pxx_run_initializers was never ...".
  Before this fix it stopped earlier, at assert, so it is not a regression.
