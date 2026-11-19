---
slug: bug-test-core-four-rows-still-red-2026-11-19
track: T
prio: 30
type: bug
status: backlog
owner: unassigned
created: 2026-11-19
found-by: rd, full `make -i test-core` on b2cd388a0c (after bug-test-core-stops-at-freebsd-kernel-entries-5-not-2)
tags: [test-core, cfront, inline-asm, crtl]
blocked-by: []
summary: "Four test-core rows are still red after the 2026-11-19 sweep, each a real gap rather than a stale row: casmmpress26 (nine dereferenced \"m\" operands exceed the inline-asm pool, regression from b3c5f711ea), c_host_header_needs_cdefs_glue (crtl's sigset_t conflicts with glibc's bits/types/sigset_t.h through <spawn.h>; red since at least v455), test_c_crypt26 (`uses crypt` wants libxcrypt's crypt_r/crypt_data, but crtl's own <crypt.h> shadows the host one since b1b534c3c6; red at v455 too), and c_incomplete_type_member_refused's i386 side (bug-c-aligned-alignof-long-double-on-i386). test-core still stops at the first of them that it reaches."
---

# test-core: four rows still red (2026-11-19)

All 28 failures of the 2026-11-19 `make -i test-core` were classified;
everything stale was graduated in the freebsd ticket's commit. These four are left:

1. **casmmpress26** (`test/casm_m_operand_pressure.c`): "inline asm needs more
   registers than this frontend can pin -- a fixed caller-saved pool of 9".
   Since b3c5f711ea a dereferenced "m" operand binds the object through a
   pool register (bug-c-an-m-operand-that-is-a-dereference-binds-a-copy), so
   nine such operands exhaust the pool. Fix direction: an "m" on `*p` where p
   is already a register or a frame slot needs no extra register (address it
   in place), or spill to the frame when the pool runs out. gcc compiles it.

2. **c_host_header_needs_cdefs_glue**: `#include <spawn.h>` resolves from
   /usr/include and pulls glibc's `bits/types/sigset_t.h`
   (`typedef __sigset_t sigset_t`), which conflicts with crtl's
   `signal.h` `typedef struct { unsigned long __val[16]; } sigset_t`. At
   v455 it failed earlier (`'loc' undeclared`). Options: crtl ships
   <spawn.h>/<semaphore.h>/<search.h>/<ftw.h> itself (the warnings list the
   host ones it took), or the conflict check accepts two structurally
   identical structs. The first matches the "no host headers" direction.

3. **test_c_crypt26** (`test/test_c_crypt.pas`, `uses crypt`): unknown type
   crypt_data, undefined crypt_r. crtl's `<crypt.h>` (added for dropbear in
   b1b534c3c6) has only `crypt()`. Either crtl grows crypt_r and struct
   crypt_data (libxcrypt layout), or the test names the host libcrypt
   explicitly.

4. **i386 aligned(__alignof__(long double))**: see
   bug-c-aligned-alignof-long-double-on-i386. The test-core row counts the
   warning on x86-64, where the result matches gcc, so the row itself is
   green; it is listed here because it is the one place the 2026-11-19 sweep
   accepted a known divergence.

Also seen while classifying (not a row): pxx accepts two definitions of one
`static` function in one TU with a warning, and two definitions of one
`static` variable silently (`static int a = 1; ... static int a = 2;` reads
2). gcc refuses both ("redefinition"). Worth its own ticket if anyone
relies on unity builds.
