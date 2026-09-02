/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: fcntl — libc-free file open + advisory-lock veneer for sqlite's
 * unix VFS. open()/openat()/creat() bottom out on __pxx_open (the shared PAL
 * open path, same one fopen uses); fcntl() forwards to __pxx_fcntl, a thin
 * pass-through to the fcntl(2) syscall. The `struct flock` the caller builds
 * matches the kernel's native layout on each target because off_t == the native
 * `long` (4 on ILP32, 8 on LP64), so no field translation is needed.
 */

#include <fcntl.h>
#include <stdarg.h>
#include <errno.h>
#include <unistd.h>
#include <sys/syscall.h>

extern int __pxx_open(const char *path, int flags, int mode);
extern int __pxx_fcntl(int fd, int cmd, long long arg);

/* The PAL returns the RAW kernel convention: a negative errno, not -1/errno.
   Every function here used to return that straight to the caller, so
   open("/missing") returned -2 and open("/", O_WRONLY) returned -21, with errno
   left untouched. `if (fd < 0)` still caught it, but `if (fd == -1)` did not,
   and perror()/strerror(errno) after a failed open printed "Success". unistd.c
   already converts on read/write/close/lseek; this file never did.
   Found by tools/gcc_diff_probe.sh. */
static int sysret(int rc) {
  if (rc < 0) { errno = -rc; return -1; }
  return rc;
}

int open(const char *path, int flags, ...) {
  int mode = 0;
  if (flags & O_CREAT) {
    va_list ap;
    va_start(ap, flags);
    mode = va_arg(ap, int);
    va_end(ap);
  }
  return sysret(__pxx_open(path, flags, mode));
}

int openat(int dirfd, const char *path, int flags, ...) {
  int mode = 0;
  if (flags & O_CREAT) {
    va_list ap;
    va_start(ap, flags);
    mode = va_arg(ap, int);
    va_end(ap);
  }
  /* Only AT_FDCWD (-100) is supported; sqlite's default VFS uses plain open(). */
  if (dirfd != -100) { errno = EBADF; return -1; }
  return sysret(__pxx_open(path, flags, mode));
}

int creat(const char *path, mode_t mode) {
  return sysret(__pxx_open(path, O_CREAT | O_WRONLY | O_TRUNC, (int)mode));
}

int fcntl(int fd, int cmd, ...) {
  va_list ap;
  long arg;
  va_start(ap, cmd);
  arg = va_arg(ap, long);   /* int (F_SETFL) or struct flock* — both fit a native long */
  va_end(ap);
  return sysret(__pxx_fcntl(fd, cmd, (long long)arg));
}

/* LFS (_LARGEFILE64_SOURCE) aliases sqlite's os_unix.c imports. off_t is already
   64-bit on LP64 and the native long on ILP32, so the *64 names are the SAME
   syscall path as the base ones — forward, no field translation. */
int open64(const char *path, int flags, ...) {
  int mode = 0;
  if (flags & O_CREAT) {
    va_list ap;
    va_start(ap, flags);
    mode = va_arg(ap, int);
    va_end(ap);
  }
  return sysret(__pxx_open(path, flags, mode));
}

int fcntl64(int fd, int cmd, ...) {
  va_list ap;
  long arg;
  va_start(ap, cmd);
  arg = va_arg(ap, long);
  va_end(ap);
  return sysret(__pxx_fcntl(fd, cmd, (long long)arg));
}

/* fallocate(2) and posix_fallocate(3).

   THE SYSCALL IS THE SAME ONE AND THE ERROR CONVENTIONS ARE NOT. fallocate
   returns -1 with errno set; posix_fallocate returns the error NUMBER and
   leaves errno alone. busybox's util-linux/fallocate.c depends on the second
   one exactly -- `if ((errno = posix_fallocate(fd, ofs, len)) != 0)' -- so an
   implementation that returned -1/errno would store -1 into errno and print
   "Unknown error -1" on every failure, while looking correct at a glance.

   syscall() in <unistd.h> has already turned the kernel's negative errno into
   -1-plus-errno, so posix_fallocate reads errno BACK rather than negating a
   return value. Doing it the other way -- calling __pxx_syscall directly to
   keep the raw value -- would work too and would put a second spelling of the
   same call in the tree; see the note in src/sys/statfs.c about the two
   conventions that already exist here.

   FOUR ARGUMENTS ON A 64-BIT TARGET AND SIX ON A 32-BIT ONE. The kernel's
   offset and len are loff_t -- 64 bits on every architecture, including the
   ones where `long' is 32 -- and a 32-bit target passes each as a LO/HI
   register pair. Handing the syscall four arguments there leaves the two high
   words as whatever was in those registers, so the call does not fail: it
   allocates at a random multi-gigabyte offset. crtl's own off_t is `long' and
   is therefore 32 bits on those targets, so the high word is always the sign
   extension and never anything else -- but it has to be PASSED, and passing it
   is the whole of the difference. Little-endian on all four targets, so lo
   first. */
#if !defined(SYS_fallocate)

/* arm32 and xtensa: <sys/syscall.h> names no numbers for them on purpose.
   THE GUARD IS A PREPROCESSOR TEST AND NOT A USE OF SYS_fallocate, because
   pxx's C frontend turns an undeclared identifier into 0 with a warning -- so
   the unguarded version of this file compiled for arm32 and called syscall
   number 0. Measured here 2026-09-02: the arm32 rows of
   test/c_crtl_fallocate.c came back wrong rather than absent. Same trap as
   src/sys/statfs.c and src/sys/select.c; filed as
   bug-c-an-undeclared-identifier-used-as-a-value-is-a-warning-not-an-error. */
static long pxx_fallocate_raw(int fd, int mode, off_t offset, off_t len) {
  (void)fd; (void)mode; (void)offset; (void)len;
  errno = ENOSYS;
  return -1;
}

#elif __SIZEOF_LONG__ == 8

static long pxx_fallocate_raw(int fd, int mode, off_t offset, off_t len) {
  return syscall(SYS_fallocate, (long)fd, (long)mode, (long)offset, (long)len);
}

#else

static long pxx_fallocate_raw(int fd, int mode, off_t offset, off_t len) {
  long long off64 = (long long)offset;
  long long len64 = (long long)len;
  return syscall(SYS_fallocate, (long)fd, (long)mode,
                 (long)(off64 & 0xFFFFFFFFLL), (long)(off64 >> 32),
                 (long)(len64 & 0xFFFFFFFFLL), (long)(len64 >> 32));
}

#endif

int fallocate(int fd, int mode, off_t offset, off_t len) {
  return pxx_fallocate_raw(fd, mode, offset, len) < 0 ? -1 : 0;
}

int posix_fallocate(int fd, off_t offset, off_t len) {
  int saved = errno;
  int rc;
  errno = 0;
  if (pxx_fallocate_raw(fd, 0, offset, len) < 0) {
    rc = errno;
    errno = saved;
    return rc;
  }
  errno = saved;
  return 0;
}
