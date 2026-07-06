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

extern int __pxx_open(const char *path, int flags, int mode);
extern int __pxx_fcntl(int fd, int cmd, long long arg);

int open(const char *path, int flags, ...) {
  int mode = 0;
  if (flags & O_CREAT) {
    va_list ap;
    va_start(ap, flags);
    mode = va_arg(ap, int);
    va_end(ap);
  }
  return __pxx_open(path, flags, mode);
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
  if (dirfd != -100) return -1;
  return __pxx_open(path, flags, mode);
}

int creat(const char *path, mode_t mode) {
  return __pxx_open(path, O_CREAT | O_WRONLY | O_TRUNC, (int)mode);
}

int fcntl(int fd, int cmd, ...) {
  va_list ap;
  long arg;
  va_start(ap, cmd);
  arg = va_arg(ap, long);   /* int (F_SETFL) or struct flock* — both fit a native long */
  va_end(ap);
  return __pxx_fcntl(fd, cmd, (long long)arg);
}
