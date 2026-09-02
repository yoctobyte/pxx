/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: capget(2) and capset(2).
 *
 * CAPGET WITH AN UNSUPPORTED VERSION IS NOT SIMPLY AN ERROR: the kernel writes
 * the version it DOES support back into the header and then returns
 * -1/EINVAL. That is the negotiation, and it is why the header argument is not
 * const while capset's data is -- a caller retries with what came back.
 * busybox's libbb/capability.c depends on exactly that.
 *
 * #ifdef ON THE SYSCALL NUMBER, not on the architecture -- see src/sched.c.
 * These are declared in <linux/capability.h> rather than in a sys/ header
 * because that is where the kernel and libcap both put them.
 */
#include <linux/capability.h>
#include <errno.h>
#include <unistd.h>
#include <sys/syscall.h>

int capget(cap_user_header_t header, cap_user_data_t data)
{
#ifdef SYS_capget
  return (int)syscall(SYS_capget, (long)header, (long)data);
#else
  (void)header; (void)data;
  errno = ENOSYS;
  return -1;
#endif
}

int capset(cap_user_header_t header, const cap_user_data_t data)
{
#ifdef SYS_capset
  return (int)syscall(SYS_capset, (long)header, (long)data);
#else
  (void)header; (void)data;
  errno = ENOSYS;
  return -1;
#endif
}
