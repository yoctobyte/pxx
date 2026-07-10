/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_UNISTD_H
#define PXX_CRTL_UNISTD_H 1

#include <stddef.h>
#include <sys/types.h>

#define STDIN_FILENO 0
#define STDOUT_FILENO 1
#define STDERR_FILENO 2
#define _SC_PAGESIZE 30
#define _SC_PAGE_SIZE _SC_PAGESIZE

/* access(2) mode bits (POSIX <unistd.h>). Match the Linux kernel values so a
   real access() syscall interprets them; without these sqlite's access(path,
   F_OK) silently passed mode 0 (== F_OK, so it happened to work). */
#define F_OK 0
#define X_OK 1
#define W_OK 2
#define R_OK 4

int close(int fd);
ssize_t read(int fd, void *buf, size_t count);
ssize_t write(int fd, const void *buf, size_t count);
off_t lseek(int fd, off_t offset, int whence);
ssize_t pread(int fd, void *buf, size_t count, off_t offset);
ssize_t pwrite(int fd, const void *buf, size_t count, off_t offset);
int fsync(int fd);
int getpid(void);
char *getcwd(char *buf, size_t size);
int unlink(const char *path);
int rmdir(const char *path);
int ftruncate(int fd, off_t length);
int access(const char *path, int mode);
int fchown(int fd, uid_t owner, gid_t group);
uid_t geteuid(void);
ssize_t readlink(const char *path, char *buf, size_t bufsz);
int execvp(const char *file, char *const argv[]);
long sysconf(int name);

#endif
