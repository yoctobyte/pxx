/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: sys/stat — libc-free stat/fstat/lstat/mkdir/fchmod for sqlite's
 * unix VFS. The three stat variants call the Pascal PAL, which issues statx(2)
 * (arch-neutral: one struct layout on every target) and returns the fields
 * sqlite needs in the fixed __pxx_statbuf record below. sqlite keys its POSIX
 * lock manager on (st_dev, st_ino), so those come back real, not zeroed.
 */

#include <sys/stat.h>
#include <errno.h>

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
  /* Appended, so the existing field offsets are unchanged. These were
     hardcoded in fill() below — nlink to 1, uid/gid/rdev to 0, and atime and
     ctime to mtime — which is silently wrong for anything that compares them.
     statx returns all of them; they were simply never carried across. */
  long long nlink;
  long long rdev;
  long long atime;
  long long ctime;
  int       uid;
  int       gid;
};

extern int __pxx_fstat(int fd, struct __pxx_statbuf *sb);
extern int __pxx_stat(const char *path, struct __pxx_statbuf *sb);
extern int __pxx_lstat(const char *path, struct __pxx_statbuf *sb);
extern int __pxx_mkdir(const char *path, int mode);
extern int __pxx_fchmod(int fd, int mode);
extern int __pxx_chmod(const char *path, int mode);
extern int __pxx_mknod(const char *path, int mode, long long dev);
extern int __pxx_umask(int mask);

static void fill(struct stat *buf, const struct __pxx_statbuf *sb) {
  buf->st_dev     = (dev_t)sb->dev;
  buf->st_ino     = (ino_t)sb->ino;
  buf->st_mode    = (mode_t)sb->mode;
  buf->st_nlink   = (nlink_t)sb->nlink;
  buf->st_uid     = (uid_t)sb->uid;
  buf->st_gid     = (gid_t)sb->gid;
  buf->st_rdev    = (dev_t)sb->rdev;
  buf->st_size    = (off_t)sb->size;
  buf->st_blksize = (blksize_t)sb->blksize;
  buf->st_blocks  = (blkcnt_t)sb->blocks;
  buf->st_atime   = (long)sb->atime;
  buf->st_mtime   = (long)sb->mtime;
  buf->st_ctime   = (long)sb->ctime;
}

/* The PAL stat calls return the raw syscall result: 0 on success, -errno on
   failure. Propagate -errno into errno — callers (notably sqlite's path
   resolver, appendOnePathElement) branch on `errno==ENOENT` to tell "file does
   not exist yet" (fine, create it) from a real error; without this, a stale
   errno made a missing file look like an I/O error and sqlite3_open a
   non-:memory: db returned SQLITE_CANTOPEN. */
int fstat(int fd, struct stat *buf) {
  struct __pxx_statbuf sb;
  int r = __pxx_fstat(fd, &sb);
  if (r >= 0) { fill(buf, &sb); return 0; }
  errno = -r;
  return -1;
}

int stat(const char *path, struct stat *buf) {
  struct __pxx_statbuf sb;
  int r = __pxx_stat(path, &sb);
  if (r >= 0) { fill(buf, &sb); return 0; }
  errno = -r;
  return -1;
}

int lstat(const char *path, struct stat *buf) {
  struct __pxx_statbuf sb;
  int r = __pxx_lstat(path, &sb);
  if (r >= 0) { fill(buf, &sb); return 0; }
  errno = -r;
  return -1;
}

/* LFS (_LARGEFILE64_SOURCE) aliases sqlite's os_unix.c imports. On LP64 st_size
   is already 64-bit and `struct stat64` == `struct stat`, so the *64 calls share
   the base path — the PAL statx already returns a 64-bit size. */
int fstat64(int fd, struct stat *buf)          { return fstat(fd, buf); }
int stat64(const char *path, struct stat *buf) { return stat(path, buf); }
int lstat64(const char *path, struct stat *buf){ return lstat(path, buf); }

/* The PAL returns the raw kernel convention (0, or a NEGATIVE errno). These two
   forwarded it straight out, so mkdir() on a missing parent returned -2 with
   errno untouched instead of -1/ENOENT. Found by tools/gcc_diff_probe.sh. */
int mkdir(const char *path, mode_t mode) {
  int rc = __pxx_mkdir(path, (int)mode);
  if (rc < 0) { errno = -rc; return -1; }
  return 0;
}

int fchmod(int fd, mode_t mode) {
  int rc = __pxx_fchmod(fd, (int)mode);
  if (rc < 0) { errno = -rc; return -1; }
  return 0;
}

int chmod(const char *path, mode_t mode) {
  int rc = __pxx_chmod(path, (int)mode);
  if (rc < 0) { errno = -rc; return -1; }
  return 0;
}

/* mknod creates a FIFO, a device node or a regular file, picked by the file
   type bits of `mode`. `dev` is consulted only for S_IFCHR/S_IFBLK, which is
   why mkfifo below can pass 0 and why busybox's libbb/copy_file.c -- which
   recreates whatever node type it found while copying a tree -- reaches this
   for FIFOs and sockets far more often than for real devices. */
int mknod(const char *path, mode_t mode, dev_t dev) {
  int rc = __pxx_mknod(path, (int)mode, (long long)dev);
  if (rc < 0) { errno = -rc; return -1; }
  return 0;
}

/* mkfifo IS mknod with S_IFIFO and no device number -- POSIX defines it that
   way, so it is spelled that way rather than given its own syscall path. */
int mkfifo(const char *path, mode_t mode) {
  return mknod(path, (mode & ~S_IFMT) | S_IFIFO, 0);
}

/* umask cannot fail and returns the PREVIOUS mask, so there is no -1/errno
   path here — the raw PAL result IS the answer. */
mode_t umask(mode_t mask) {
  return (mode_t)__pxx_umask((int)mask);
}
