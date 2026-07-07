/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: unistd — libc-free fsync/getpid/sysconf for sqlite's unix VFS.
 * fsync/getpid forward to the Pascal PAL syscalls; sysconf answers the one
 * query sqlite makes (_SC_PAGESIZE) from a constant, no syscall.
 */

#include <unistd.h>
#include <errno.h>

extern int __pxx_fsync(int fd);
extern int __pxx_getpid(void);
extern int __pxx_getcwd(char *buf, unsigned long size);
extern int __pxx_remove(const char *path);

int fsync(int fd) { return __pxx_fsync(fd); }

int getpid(void) { return __pxx_getpid(); }

/* Kernel getcwd returns the path length incl. NUL, or -errno. */
char *getcwd(char *buf, size_t size) {
  int r = __pxx_getcwd(buf, (unsigned long)size);
  if (r < 0) { errno = -r; return 0; }
  return buf;
}

/* Link-only stub: no PATH walk / PalExecve bridge yet. Callers see a failed
   exec (tcc's -run re-exec corner) and carry on. */
int execvp(const char *file, char *const argv[]) {
  (void)file; (void)argv;
  errno = 2; /* ENOENT */
  return -1;
}

/* unlink(2) on a file == the PAL's remove (unlinkat, no REMOVEDIR). */
int unlink(const char *path) {
  int rc = __pxx_remove(path);
  if (rc < 0) { errno = -rc; return -1; }
  return 0;
}

long sysconf(int name) {
  if (name == _SC_PAGESIZE) return 4096;
  return -1;
}
