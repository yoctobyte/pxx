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

extern void *__pxx_mmap_anon_prot(long length, int prot);
extern int __pxx_mprotect(void *addr, long length, int prot);
extern int __pxx_munmap(void *addr, long length);

/* ANONYMOUS mappings are real now, over the PAL. That is what a JIT needs:
   tcc -run maps pages, writes code into them and jumps in, which the old
   MAP_FAILED stub made impossible.

   FILE-BACKED mmap is still refused with MAP_FAILED, deliberately. sqlite is
   the only in-tree caller and its mmap I/O is off by default
   (SQLITE_MAX_MMAP_SIZE = 0), so it falls back to ordinary read/write — which
   also sidesteps the 32-bit mmap2 page-offset ABI. A wrong file mapping would
   be a silent data bug; a refusal is a fallback. */
void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
  void *p;
  (void)addr; (void)offset;
  if (!(flags & MAP_ANONYMOUS) || fd != -1) return MAP_FAILED;
  p = __pxx_mmap_anon_prot((long)length, prot);
  /* the raw syscall returns -errno in the top page on failure */
  if ((unsigned long)p >= (unsigned long)-4095L) return MAP_FAILED;
  return p;
}

/* LFS alias: sqlite's os_unix.c imports mmap64 under _LARGEFILE64_SOURCE. Same
   stub-fallback behaviour as mmap (mmap I/O is off by default). */
void *mmap64(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
  return mmap(addr, length, prot, flags, fd, offset);
}

int munmap(void *addr, size_t length) {
  if (!addr) return 0;
  return __pxx_munmap(addr, (long)length) < 0 ? -1 : 0;
}

/* Real now — tcc's protect_pages needs it to flip written code pages to
   executable. A no-op success here used to be honest only because nothing was
   ever really mapped; with anonymous mmap live it would be a lie. */
int mprotect(void *addr, size_t length, int prot) {
  if (!addr) return 0;
  return __pxx_mprotect(addr, (long)length, prot) < 0 ? -1 : 0;
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
