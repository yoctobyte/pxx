/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_SYS_MMAN_H
#define PXX_CRTL_SYS_MMAN_H 1

/* Minimal mmap surface for sqlite's optional memory-mapped I/O. Declarations
   only; a `:memory:` database never maps a file. Flag values = Linux ABI. */

#include <sys/types.h>

#define PROT_NONE  0x0
#define PROT_READ  0x1
#define PROT_WRITE 0x2
#define PROT_EXEC  0x4

#define MAP_SHARED    0x01
#define MAP_PRIVATE   0x02
#define MAP_FIXED     0x10
#define MAP_ANONYMOUS 0x20

#define MAP_FAILED ((void *)-1)

#define MS_ASYNC      1
#define MS_INVALIDATE 2
#define MS_SYNC       4

extern void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset);
extern int   munmap(void *addr, size_t length);
extern int   mprotect(void *addr, size_t length, int prot);
extern int   msync(void *addr, size_t length, int flags);
/* mremap(2)'s flags. Linux ABI values, same as <linux/mman.h>.

   THE HEADER DECLARED mremap AND DEFINED NONE OF ITS FLAGS, which is not a
   smaller surface -- it is an inconsistent one. A caller cannot use the
   declaration without them, so the declaration alone buys nothing and costs a
   compile error at the call site instead of at the include. sys/mman.c's own
   comment names MREMAP_FIXED while this header defined it nowhere.

   MEASURED 2026-09-05: sqlite3.c takes `#if defined(__GNUC__) && !defined(
   _GNU_SOURCE) -> #define _GNU_SOURCE` at :248, which makes HAVE_MREMAP 1 at
   :38729, which reaches osMremap(..., MREMAP_MAYMOVE, ...) -- and the build
   died with `undeclared identifier 'MREMAP_MAYMOVE' used as value` on all four
   arches (x86_64, i386, arm32, aarch64). Reproduced locally at HEAD against a
   corpus untouched since August, so it is the tree and not a box.

   mremap itself is a stub that fails with ENOMEM and never reads flags, so
   these are a COMPILE surface only. That is the right shape: sqlite passes the
   flag, gets MAP_FAILED, and takes its own fallback. */
#define MREMAP_MAYMOVE   1
#define MREMAP_FIXED     2
#define MREMAP_DONTUNMAP 4

extern void *mremap(void *old_address, size_t old_size, size_t new_size, int flags, ...);

/* mlock/munlock(2): pin a range in RAM, and release it. BOTH, not just mlock:
   busybox miscutils/hdparm.c pins its timing buffer at :1507 and releases it at
   :1559, so a crtl with only mlock moves the refusal fifty lines down the same
   file rather than clearing it. */
extern int   mlock(const void *addr, size_t len);
extern int   munlock(const void *addr, size_t len);

#endif
