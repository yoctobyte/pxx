/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: personality(2).
 *
 * THE SUCCESSFUL RETURN IS THE *PREVIOUS* PERSONALITY, not the new one, which
 * is what makes personality(0xffffffff) a query: 0xffffffff is not a valid
 * personality, the kernel rejects the set, and the old value comes back
 * unchanged. Every caller that wants to read the current value does that.
 *
 * #ifdef ON THE SYSCALL NUMBER, not on the architecture -- see src/sched.c.
 */
#include <sys/personality.h>
#include <errno.h>
#include <unistd.h>
#include <sys/syscall.h>

int personality(unsigned long persona)
{
#ifdef SYS_personality
  return (int)syscall(SYS_personality, (long)persona);
#else
  (void)persona;
  errno = ENOSYS;
  return -1;
#endif
}
