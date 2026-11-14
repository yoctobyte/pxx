/* SPDX-License-Identifier: Zlib */
/* C runtime: eventfd (see <sys/eventfd.h>). eventfd2 is the only form on the
   newer ABIs (aarch64, riscv) and exists everywhere else too. */
#include <sys/eventfd.h>
#include <sys/syscall.h>
#include <unistd.h>

int eventfd(unsigned int initval, int flags)
{
  return (int)syscall(SYS_eventfd2, (long)initval, (long)flags);
}

/* glibc's helpers: 0 on a full 8-byte transfer, -1 otherwise */
int eventfd_read(int fd, eventfd_t *value)
{
  return read(fd, value, sizeof *value) == (ssize_t)sizeof *value ? 0 : -1;
}

int eventfd_write(int fd, eventfd_t value)
{
  return write(fd, &value, sizeof value) == (ssize_t)sizeof value ? 0 : -1;
}
