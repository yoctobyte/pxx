/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_SYS_STAT_H
#define PXX_CRTL_SYS_STAT_H 1

/* Minimal POSIX stat surface for sqlite's unix VFS. Declarations only — a
   `:memory:` database never calls these, but the source must compile and the
   symbols resolve on a libc-free cross link. */

#include <sys/types.h>

typedef unsigned long nlink_t;
typedef long          blksize_t;
typedef long          blkcnt_t;

struct stat {
  dev_t     st_dev;
  ino_t     st_ino;
  mode_t    st_mode;
  nlink_t   st_nlink;
  uid_t     st_uid;
  gid_t     st_gid;
  dev_t     st_rdev;
  off_t     st_size;
  blksize_t st_blksize;
  blkcnt_t  st_blocks;
  long      st_atime;
  long      st_mtime;
  long      st_ctime;
};

/* file type bits */
#define S_IFMT   0170000
#define S_IFSOCK 0140000
#define S_IFLNK  0120000
#define S_IFREG  0100000
#define S_IFBLK  0060000
#define S_IFDIR  0040000
#define S_IFCHR  0020000
#define S_IFIFO  0010000

#define S_ISUID  0004000
#define S_ISGID  0002000
#define S_ISVTX  0001000

/* permission bits */
#define S_IRWXU  0000700
#define S_IRUSR  0000400
#define S_IWUSR  0000200
#define S_IXUSR  0000100
#define S_IRWXG  0000070
#define S_IRGRP  0000040
#define S_IWGRP  0000020
#define S_IXGRP  0000010
#define S_IRWXO  0000007
#define S_IROTH  0000004
#define S_IWOTH  0000002
#define S_IXOTH  0000001

#define S_ISLNK(m)  (((m) & S_IFMT) == S_IFLNK)
#define S_ISREG(m)  (((m) & S_IFMT) == S_IFREG)
#define S_ISDIR(m)  (((m) & S_IFMT) == S_IFDIR)
#define S_ISCHR(m)  (((m) & S_IFMT) == S_IFCHR)
#define S_ISBLK(m)  (((m) & S_IFMT) == S_IFBLK)
#define S_ISFIFO(m) (((m) & S_IFMT) == S_IFIFO)
#define S_ISSOCK(m) (((m) & S_IFMT) == S_IFSOCK)

extern int stat(const char *path, struct stat *buf);
extern int fstat(int fd, struct stat *buf);
extern int lstat(const char *path, struct stat *buf);
extern int mkdir(const char *path, mode_t mode);
extern int chmod(const char *path, mode_t mode);
extern int fchmod(int fd, mode_t mode);
extern mode_t umask(mode_t mask);

#endif
