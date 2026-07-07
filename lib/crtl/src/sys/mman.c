/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: sys/mman — sqlite's memory-mapped I/O is OFF by default
 * (SQLITE_MAX_MMAP_SIZE default mmap_size = 0), so mmap is never called at
 * runtime; it only has to resolve as a symbol on the libc-free link. Returning
 * MAP_FAILED makes sqlite fall back to ordinary read/write even if a build ever
 * enables mmap, which sidesteps the 32-bit mmap2 page-offset ABI. munmap is a
 * no-op success.
 */

#include <sys/mman.h>
#include <stddef.h>

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
  (void)addr; (void)length; (void)prot; (void)flags; (void)fd; (void)offset;
  return MAP_FAILED;
}

int munmap(void *addr, size_t length) {
  (void)addr; (void)length;
  return 0;
}

/* No-op success: pairs with the stub mmap above (nothing is ever really
   mapped). tcc's protect_pages calls it; real exec-page support needs the
   PAL-backed mmap first. */
int mprotect(void *addr, size_t length, int prot) {
  (void)addr; (void)length; (void)prot;
  return 0;
}
