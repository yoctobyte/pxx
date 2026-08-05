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
#include <errno.h>

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
  (void)addr; (void)length; (void)prot; (void)flags; (void)fd; (void)offset;
  return MAP_FAILED;
}

/* LFS alias: sqlite's os_unix.c imports mmap64 under _LARGEFILE64_SOURCE. Same
   stub-fallback behaviour as mmap (mmap I/O is off by default). */
void *mmap64(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
  return mmap(addr, length, prot, flags, fd, offset);
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

/* Flushing a mapping nothing ever created is vacuously done — no-op success,
   the same answer munmap and mprotect give for the same reason.

   These two were DECLARED in sys/mman.h with no body, which is the worse
   failure: the C frontend's unresolved-extern fallback bound a caller to
   libc.so.6, so the program kept working and quietly stopped being
   self-contained (tools/crtl_decl_probe.sh exists to catch exactly that). A
   stub that matches the rest of this file is honest; a silent DT_NEEDED is
   not. */
int msync(void *addr, size_t length, int flags) {
  (void)addr; (void)length; (void)flags;
  return 0;
}

/* mremap must return a POINTER, so it cannot pretend the way msync can: with
   mmap stubbed out there is never a mapping to grow, and the caller has to see
   that. Fails like mmap does. Linux-specific and variadic (the optional 5th
   arg is new_address under MREMAP_FIXED); the varargs are simply not read. */
void *mremap(void *old_address, size_t old_size, size_t new_size, int flags, ...) {
  (void)old_address; (void)old_size; (void)new_size; (void)flags;
  errno = ENOMEM;
  return MAP_FAILED;
}
