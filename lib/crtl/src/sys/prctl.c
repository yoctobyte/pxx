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
#include <stdarg.h>

/* Variadic, as glibc's: four longs are read whatever the caller passed, and
 * the kernel looks only at the ones the option defines (glibc does the
 * same). */
int prctl(int option, ...)
{
  va_list ap;
  unsigned long arg2, arg3, arg4, arg5;
  va_start(ap, option);
  arg2 = va_arg(ap, unsigned long);
  arg3 = va_arg(ap, unsigned long);
  arg4 = va_arg(ap, unsigned long);
  arg5 = va_arg(ap, unsigned long);
  va_end(ap);
#ifdef SYS_prctl
  return (int)syscall(SYS_prctl, (long)option, (long)arg2, (long)arg3,
                      (long)arg4, (long)arg5);
#else
  (void)option; (void)arg2; (void)arg3; (void)arg4; (void)arg5;
  errno = ENOSYS;
  return -1;
#endif
}
