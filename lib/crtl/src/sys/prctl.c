/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: prctl(2).
 *
 * #ifdef ON THE SYSCALL NUMBER, not on the architecture -- see src/sched.c for
 * why (an undeclared SYS_ becomes 0 and the call lands on syscall zero).
 * syscall() has already turned -errno into -1 plus errno.
 */
#include <sys/prctl.h>
#include <errno.h>
#include <unistd.h>
#include <sys/syscall.h>

int prctl(int option, unsigned long arg2, unsigned long arg3,
          unsigned long arg4, unsigned long arg5)
{
#ifdef SYS_prctl
  return (int)syscall(SYS_prctl, (long)option, (long)arg2, (long)arg3,
                      (long)arg4, (long)arg5);
#else
  (void)option; (void)arg2; (void)arg3; (void)arg4; (void)arg5;
  errno = ENOSYS;
  return -1;
#endif
}
