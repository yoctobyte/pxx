/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: flock(2).
 *
 * #ifdef ON THE SYSCALL NUMBER, not on the architecture -- see src/sched.c for
 * why (an undeclared SYS_ becomes 0 and the call lands on syscall zero).
 * syscall() has already turned -errno into -1 plus errno, so LOCK_NB failing
 * arrives here as -1/EWOULDBLOCK, which is what a caller polling for the lock
 * is testing.
 */
#include <sys/file.h>
#include <errno.h>
#include <unistd.h>
#include <sys/syscall.h>

int flock(int fd, int operation)
{
#ifdef SYS_flock
  return (int)syscall(SYS_flock, (long)fd, (long)operation);
#else
  (void)fd; (void)operation;
  errno = ENOSYS;
  return -1;
#endif
}
