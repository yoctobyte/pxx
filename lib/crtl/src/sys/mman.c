/*
 * C runtime: sys/mman -- the kernel's mapping calls (mmap, munmap, mprotect,
 * msync, mremap, madvise, mlock) as the syscalls themselves, where the target
 * has syscall numbers; without them, anonymous memory over the PAL only.
 */
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
#include <unistd.h>      /* syscall() */
#include <sys/syscall.h>
#include <stdarg.h>

extern void *__pxx_mmap_anon_prot(long length, int prot);
extern int __pxx_mprotect(void *addr, long length, int prot);
extern int __pxx_munmap(void *addr, long length);

/* mmap(2) is the kernel's own call wherever there is one: every flag, the
   address hint, the descriptor and the offset reach it unchanged. A driver
   maps a device's registers (MAP_SHARED over a VFIO device fd, at an offset
   past 4 GiB) and physically contiguous DMA memory (MAP_HUGETLB); dropping
   any of that, as the anonymous-only stub did, gave such a program a private
   zero page where it asked for a device -- or MAP_FAILED with no errno.

   The 32-bit ABIs (i386, arm32) take mmap2, whose last argument is the offset
   in 4096-byte units, so an offset that is not page aligned is EINVAL there
   as it is on 64-bit kernels. Elsewhere (no syscall numbers: --os=windows) the
   old anonymous-only path stays. sqlite is unaffected either way: its mmap
   I/O is off by default (SQLITE_MAX_MMAP_SIZE = 0). */
void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
#if defined(SYS_mmap2)
  long r;
  if ((unsigned long long)offset & 4095) { errno = EINVAL; return MAP_FAILED; }
  r = syscall(SYS_mmap2, (long)addr, (long)length, (long)prot, (long)flags, (long)fd,
              (long)((unsigned long long)offset >> 12));
  return r == -1 ? MAP_FAILED : (void *)r;
#elif defined(SYS_mmap)
  long r = syscall(SYS_mmap, (long)addr, (long)length, (long)prot, (long)flags, (long)fd, (long)offset);
  return r == -1 ? MAP_FAILED : (void *)r;
#else
  void *p;
  (void)addr; (void)offset;
  if (!(flags & MAP_ANONYMOUS) || fd != -1) { errno = ENODEV; return MAP_FAILED; }
  p = __pxx_mmap_anon_prot((long)length, prot);
  /* the raw syscall returns -errno in the top page on failure */
  if ((unsigned long)p >= (unsigned long)-4095L) { errno = (int)-(long)p; return MAP_FAILED; }
  return p;
#endif
}

/* LFS alias: sqlite's os_unix.c imports mmap64 under _LARGEFILE64_SOURCE;
   off_t is 64 bits on every crtl target, so it is the same call. */
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

/* msync(2): with file mappings real, flushing one is real too. */
int msync(void *addr, size_t length, int flags) {
#ifdef SYS_msync
  return (int)syscall(SYS_msync, (long)addr, (long)length, (long)flags);
#else
  (void)addr; (void)length; (void)flags;
  return 0;                             /* (nothing but anonymous memory to flush) */
#endif
}

/* mremap(2): Linux-specific and variadic -- the fifth argument, the new
   address, is read only under MREMAP_FIXED, as glibc and musl do. sqlite
   (HAVE_MREMAP under _GNU_SOURCE) grows its mappings with it. */
void *mremap(void *old_address, size_t old_size, size_t new_size, int flags, ...) {
#ifdef SYS_mremap
  va_list ap;
  void *new_address = 0;
  long r;
  if (flags & MREMAP_FIXED) {
    va_start(ap, flags);
    new_address = va_arg(ap, void *);
    va_end(ap);
  }
  r = syscall(SYS_mremap, (long)old_address, (long)old_size, (long)new_size, (long)flags, (long)new_address);
  return r == -1 ? MAP_FAILED : (void *)r;
#else
  (void)old_address; (void)old_size; (void)new_size; (void)flags;
  errno = ENOMEM;
  return MAP_FAILED;
#endif
}

/* madvise(2): advice, so where there is no call it is accepted and ignored,
   which POSIX allows (posix_madvise "may" act on it). */
int madvise(void *addr, size_t length, int advice) {
#ifdef SYS_madvise
  return (int)syscall(SYS_madvise, (long)addr, (long)length, (long)advice);
#else
  (void)addr; (void)length; (void)advice;
  return 0;
#endif
}

/* mlock/munlock(2). The pair, not just mlock -- busybox's hdparm pins a timing
 * buffer and releases it fifty lines later, so shipping one of the two moves
 * the refusal rather than clearing it.
 *
 * The kernel takes the range unaligned and rounds outward itself, so there is
 * no page arithmetic here; adding some would silently lock a DIFFERENT range
 * than the caller named. Both are ordinary -1/errno calls: EPERM without
 * CAP_IPC_LOCK past RLIMIT_MEMLOCK, ENOMEM for an unmapped range.
 */
int mlock(const void *addr, size_t len)
{
#ifdef SYS_mlock
  return (int)syscall(SYS_mlock, (long)addr, (long)len);
#else
  (void)addr; (void)len;
  errno = ENOSYS;
  return -1;
#endif
}

int munlock(const void *addr, size_t len)
{
#ifdef SYS_munlock
  return (int)syscall(SYS_munlock, (long)addr, (long)len);
#else
  (void)addr; (void)len;
  errno = ENOSYS;
  return -1;
#endif
}

int mlockall(int flags)
{
#ifdef SYS_mlockall
  return (int)syscall(SYS_mlockall, (long)flags);
#else
  errno = ENOSYS;
  return -1;
#endif
}

int munlockall(void)
{
#ifdef SYS_munlockall
  return (int)syscall(SYS_munlockall);
#else
  errno = ENOSYS;
  return -1;
#endif
}
