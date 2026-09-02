/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: readv/writev/preadv/pwritev.
 *
 * #ifdef ON THE SYSCALL NUMBER, not on the architecture -- see src/sched.c.
 *
 * THE OFFSET IS SPLIT LO/HI FOR preadv/pwritev, and it is not optional on a
 * 32-bit target: the kernel takes pos_l and pos_h as two separate longs on
 * EVERY architecture, 64-bit included, where pos_h is simply always 0. Passing
 * one long on a 32-bit target does not fail -- it leaves pos_h holding
 * whatever was in the register and reads at a multi-gigabyte offset, which is
 * the same shape as the fallocate loff_t split.
 */
#include <sys/uio.h>
#include <errno.h>
#include <unistd.h>
#include <sys/syscall.h>

ssize_t readv(int fd, const struct iovec *iov, int iovcnt)
{
#ifdef SYS_readv
  return (ssize_t)syscall(SYS_readv, (long)fd, (long)iov, (long)iovcnt);
#else
  (void)fd; (void)iov; (void)iovcnt;
  errno = ENOSYS;
  return -1;
#endif
}

ssize_t writev(int fd, const struct iovec *iov, int iovcnt)
{
#ifdef SYS_writev
  return (ssize_t)syscall(SYS_writev, (long)fd, (long)iov, (long)iovcnt);
#else
  (void)fd; (void)iov; (void)iovcnt;
  errno = ENOSYS;
  return -1;
#endif
}

ssize_t preadv(int fd, const struct iovec *iov, int iovcnt, off_t offset)
{
#ifdef SYS_preadv
  unsigned long long o = (unsigned long long)offset;
  return (ssize_t)syscall(SYS_preadv, (long)fd, (long)iov, (long)iovcnt,
                          (long)(unsigned long)(o & 0xffffffffu),
                          (long)(unsigned long)(o >> 32));
#else
  (void)fd; (void)iov; (void)iovcnt; (void)offset;
  errno = ENOSYS;
  return -1;
#endif
}

ssize_t pwritev(int fd, const struct iovec *iov, int iovcnt, off_t offset)
{
#ifdef SYS_pwritev
  unsigned long long o = (unsigned long long)offset;
  return (ssize_t)syscall(SYS_pwritev, (long)fd, (long)iov, (long)iovcnt,
                          (long)(unsigned long)(o & 0xffffffffu),
                          (long)(unsigned long)(o >> 32));
#else
  (void)fd; (void)iov; (void)iovcnt; (void)offset;
  errno = ENOSYS;
  return -1;
#endif
}
