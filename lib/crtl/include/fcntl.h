/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_FCNTL_H
#define PXX_CRTL_FCNTL_H 1

/* Minimal fcntl surface for sqlite's unix VFS (file open flags + advisory
   locking). Declarations only; unused with a `:memory:` database. Flag values
   match the Linux asm-generic ABI (identical across the pxx cross targets). */

#include <sys/types.h>

#define O_RDONLY   00000000
#define O_WRONLY   00000001
#define O_RDWR     00000002
#define O_ACCMODE  00000003
#define O_CREAT    00000100
#define O_EXCL     00000200
#define O_NOCTTY   00000400
#define O_TRUNC    00001000
#define O_APPEND   00002000
#define O_NONBLOCK 00004000
#define O_SYNC     04010000
#define O_DSYNC    00010000
#define O_CLOEXEC  02000000

/* fcntl commands */
#define F_DUPFD   0
#define F_GETFD   1
#define F_SETFD   2
#define F_GETFL   3
#define F_SETFL   4
#define F_GETLK   5
#define F_SETLK   6
#define F_SETLKW  7

#define FD_CLOEXEC 1

/* lock types */
#define F_RDLCK 0
#define F_WRLCK 1
#define F_UNLCK 2

struct flock {
  short  l_type;
  short  l_whence;
  off_t  l_start;
  off_t  l_len;
  int    l_pid;
};

extern int open(const char *path, int flags, ...);
extern int openat(int dirfd, const char *path, int flags, ...);
extern int creat(const char *path, mode_t mode);
extern int fcntl(int fd, int cmd, ...);

#endif
