/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: sendfile(2).
 *
 * #ifdef ON THE SYSCALL NUMBER, not on the architecture -- see src/sched.c.
 * syscall() has already turned -errno into -1 plus errno.
 */
#include <sys/sendfile.h>
#include <errno.h>
#include <unistd.h>
#include <sys/syscall.h>

ssize_t sendfile(int out_fd, int in_fd, off_t *offset, size_t count)
{
#ifdef SYS_sendfile
  return (ssize_t)syscall(SYS_sendfile, (long)out_fd, (long)in_fd, (long)offset, (long)count);
#else
  (void)out_fd; (void)in_fd; (void)offset; (void)count;
  errno = ENOSYS;
  return -1;
#endif
}
