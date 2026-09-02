/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: klogctl(2).
 *
 * THE SYSCALL IS NAMED syslog AND THE FUNCTION IS NOT. glibc renames it
 * because <syslog.h> already spends the name on the unrelated logging
 * function; SYS_syslog below is the kernel ring buffer, not that.
 *
 * #ifdef ON THE SYSCALL NUMBER, not on the architecture -- see src/sched.c.
 */
#include <sys/klog.h>
#include <errno.h>
#include <unistd.h>
#include <sys/syscall.h>

int klogctl(int type, char *bufp, int len)
{
#ifdef SYS_syslog
  return (int)syscall(SYS_syslog, (long)type, (long)bufp, (long)len);
#else
  (void)type; (void)bufp; (void)len;
  errno = ENOSYS;
  return -1;
#endif
}
