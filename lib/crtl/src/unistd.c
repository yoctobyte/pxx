/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: unistd — libc-free fsync/getpid/sysconf for sqlite's unix VFS.
 * fsync/getpid forward to the Pascal PAL syscalls; sysconf answers the one
 * query sqlite makes (_SC_PAGESIZE) from a constant, no syscall.
 */

#include <unistd.h>

extern int __pxx_fsync(int fd);
extern int __pxx_getpid(void);

int fsync(int fd) { return __pxx_fsync(fd); }

int getpid(void) { return __pxx_getpid(); }

long sysconf(int name) {
  if (name == _SC_PAGESIZE) return 4096;
  return -1;
}
