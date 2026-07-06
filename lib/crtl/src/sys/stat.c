/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: sys/stat — libc-free stat/fstat/lstat/mkdir/fchmod for sqlite's
 * unix VFS. The three stat variants call the Pascal PAL, which issues statx(2)
 * (arch-neutral: one struct layout on every target) and returns the fields
 * sqlite needs in the fixed __pxx_statbuf record below. sqlite keys its POSIX
 * lock manager on (st_dev, st_ino), so those come back real, not zeroed.
 */

#include <sys/stat.h>

/* Mirrors TPxxStatBuf (lib/rtl/pxxcio.pas): 5 x int64 + 2 x int32 = 48 bytes,
   identical layout on every target. */
struct __pxx_statbuf {
  long long size;
  long long mtime;
  long long ino;
  long long dev;
  long long blocks;
  int       mode;
  int       blksize;
};

extern int __pxx_fstat(int fd, struct __pxx_statbuf *sb);
extern int __pxx_stat(const char *path, struct __pxx_statbuf *sb);
extern int __pxx_lstat(const char *path, struct __pxx_statbuf *sb);
extern int __pxx_mkdir(const char *path, int mode);
extern int __pxx_fchmod(int fd, int mode);

static void fill(struct stat *buf, const struct __pxx_statbuf *sb) {
  buf->st_dev     = (dev_t)sb->dev;
  buf->st_ino     = (ino_t)sb->ino;
  buf->st_mode    = (mode_t)sb->mode;
  buf->st_nlink   = 1;
  buf->st_uid     = 0;
  buf->st_gid     = 0;
  buf->st_rdev    = 0;
  buf->st_size    = (off_t)sb->size;
  buf->st_blksize = (blksize_t)sb->blksize;
  buf->st_blocks  = (blkcnt_t)sb->blocks;
  buf->st_atime   = (long)sb->mtime;
  buf->st_mtime   = (long)sb->mtime;
  buf->st_ctime   = (long)sb->mtime;
}

int fstat(int fd, struct stat *buf) {
  struct __pxx_statbuf sb;
  int r = __pxx_fstat(fd, &sb);
  if (r >= 0) fill(buf, &sb);
  return r < 0 ? -1 : 0;
}

int stat(const char *path, struct stat *buf) {
  struct __pxx_statbuf sb;
  int r = __pxx_stat(path, &sb);
  if (r >= 0) fill(buf, &sb);
  return r < 0 ? -1 : 0;
}

int lstat(const char *path, struct stat *buf) {
  struct __pxx_statbuf sb;
  int r = __pxx_lstat(path, &sb);
  if (r >= 0) fill(buf, &sb);
  return r < 0 ? -1 : 0;
}

int mkdir(const char *path, mode_t mode) {
  return __pxx_mkdir(path, (int)mode);
}

int fchmod(int fd, mode_t mode) {
  return __pxx_fchmod(fd, (int)mode);
}
