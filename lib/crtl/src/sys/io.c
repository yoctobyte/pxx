/* SPDX-License-Identifier: Zlib */
/* C runtime: iopl and ioperm (see <sys/io.h>); x86 only. */
#include <sys/io.h>
#include <sys/syscall.h>
#include <unistd.h>
#include <errno.h>

int iopl(int level)
{
#ifdef SYS_iopl
  return (int)syscall(SYS_iopl, (long)level);
#else
  (void)level;
  errno = ENOSYS;
  return -1;
#endif
}

int ioperm(unsigned long from, unsigned long num, int turn_on)
{
#ifdef SYS_ioperm
  return (int)syscall(SYS_ioperm, (long)from, (long)num, (long)turn_on);
#else
  (void)from; (void)num; (void)turn_on;
  errno = ENOSYS;
  return -1;
#endif
}
