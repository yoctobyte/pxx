/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_SYS_MMAN_H
#define PXX_CRTL_SYS_MMAN_H 1

/* The mapping calls; flag values = the Linux ABI (generic: x86, ARM, RISC-V). */

#include <sys/types.h>

#define PROT_NONE  0x0
#define PROT_READ  0x1
#define PROT_WRITE 0x2
#define PROT_EXEC  0x4

#define MAP_SHARED    0x01
#define MAP_PRIVATE   0x02
#define MAP_FIXED     0x10
#define MAP_ANONYMOUS 0x20
#define MAP_ANON      MAP_ANONYMOUS
#define MAP_SHARED_VALIDATE 0x03
#define MAP_TYPE      0x0f
#define MAP_GROWSDOWN 0x0100
#define MAP_DENYWRITE 0x0800
#define MAP_EXECUTABLE 0x1000
#define MAP_LOCKED    0x2000
#define MAP_NORESERVE 0x4000
#define MAP_POPULATE  0x8000
#define MAP_NONBLOCK  0x10000
#define MAP_STACK     0x20000
#define MAP_HUGETLB   0x40000
#define MAP_SYNC      0x80000
#define MAP_FIXED_NOREPLACE 0x100000
#define MAP_HUGE_SHIFT 26
#define MAP_HUGE_MASK  0x3f
#define MAP_HUGE_2MB  (21 << MAP_HUGE_SHIFT)
#define MAP_HUGE_1GB  (30 << MAP_HUGE_SHIFT)

#define MAP_FAILED ((void *)-1)

#define MADV_NORMAL     0
#define MADV_RANDOM     1
#define MADV_SEQUENTIAL 2
#define MADV_WILLNEED   3
#define MADV_DONTNEED   4
#define MADV_FREE       8
#define MADV_REMOVE     9
#define MADV_DONTFORK   10
#define MADV_DOFORK     11
#define MADV_MERGEABLE  12
#define MADV_UNMERGEABLE 13
#define MADV_HUGEPAGE   14
#define MADV_NOHUGEPAGE 15
#define MADV_DONTDUMP   16
#define MADV_DODUMP     17

#define MS_ASYNC      1
#define MS_INVALIDATE 2
#define MS_SYNC       4

extern void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset);
extern int   munmap(void *addr, size_t length);
extern int   mprotect(void *addr, size_t length, int prot);
extern int   msync(void *addr, size_t length, int flags);
extern int   madvise(void *addr, size_t length, int advice);
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

   mremap is the real call now (where the target has syscall numbers). */
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

/* mlockall/munlockall(2): the whole address space; flags are the generic
   Linux values (nbd-client pins itself so it cannot deadlock swapping to the
   device it serves). */
#define MCL_CURRENT 1
#define MCL_FUTURE  2
#define MCL_ONFAULT 4
extern int   mlockall(int flags);
extern int   munlockall(void);

/* memfd_create(2): an anonymous file in memory. Xorg's MIT-SHM makes its
   shared segments with it (Xext/shm.c, then fcntl(F_ADD_SEALS)). The flag
   values are the kernel's (uapi linux/memfd.h). */
#define MFD_CLOEXEC       0x0001U
#define MFD_ALLOW_SEALING 0x0002U
#define MFD_HUGETLB       0x0004U
#define MFD_NOEXEC_SEAL   0x0008U
#define MFD_EXEC          0x0010U
extern int   memfd_create(const char *name, unsigned int flags);

#endif
