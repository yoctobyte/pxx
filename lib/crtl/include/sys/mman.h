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
extern int   msync(void *addr, size_t length, int flags);
extern void *mremap(void *old_address, size_t old_size, size_t new_size, int flags, ...);

#endif
