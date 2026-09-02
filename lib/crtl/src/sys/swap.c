/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: swapon(2) and swapoff(2).
 *
 * #ifdef ON THE SYSCALL NUMBER, not on the architecture -- see src/sched.c.
 * Both need CAP_SYS_ADMIN, so an unprivileged caller gets -1/EPERM from the
 * kernel rather than anything this file decides.
 */
#include <sys/swap.h>
#include <errno.h>
#include <unistd.h>
#include <sys/syscall.h>

int swapon(const char *path, int swapflags)
{
#ifdef SYS_swapon
  return (int)syscall(SYS_swapon, (long)path, (long)swapflags);
#else
  (void)path; (void)swapflags;
  errno = ENOSYS;
  return -1;
#endif
}

int swapoff(const char *path)
{
#ifdef SYS_swapoff
  return (int)syscall(SYS_swapoff, (long)path);
#else
  (void)path;
  errno = ENOSYS;
  return -1;
#endif
}
