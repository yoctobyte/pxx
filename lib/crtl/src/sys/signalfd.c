/* SPDX-License-Identifier: Zlib */
/* C runtime: signalfd (see <sys/signalfd.h>). signalfd4 is the only form on
   the newer ABIs (aarch64, riscv) and exists everywhere else too. The kernel's
   sigset is _NSIG/8 = 8 bytes; it reads only that much of crtl's larger
   sigset_t, whose first word holds signals 1..64 as the kernel lays them out. */
#include <sys/signalfd.h>
#include <sys/syscall.h>
#include <errno.h>
#include <unistd.h>

int signalfd(int fd, const sigset_t *mask, int flags)
{
#ifdef SYS_signalfd4
  return (int)syscall(SYS_signalfd4, (long)fd, (long)mask, 8L, (long)flags);
#else
  errno = ENOSYS;
  return -1;
#endif
}
