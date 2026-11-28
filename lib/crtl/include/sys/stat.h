/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_SYS_STAT_H
#define PXX_CRTL_SYS_STAT_H 1

/* Minimal POSIX stat surface for sqlite's unix VFS. Declarations only — a
   `:memory:` database never calls these, but the source must compile and the
   symbols resolve on a libc-free cross link. */

#include <sys/types.h>
#include <time.h>   /* struct timespec, for st_atim & co */

typedef unsigned long nlink_t;
typedef long          blksize_t;
/* 64-bit like glibc's, for the reason in <sys/types.h>: statx gives stx_blocks
   as a u64, and 32 bits of 512-byte blocks stops at 2TB. Reasoned, not
   observed -- no file on this host is large enough to show it. */
typedef long long     blkcnt_t;

#if defined(__x86_64__)
/* x86-64: the kernel's and glibc's layout exactly (asm/stat.h; 144 bytes:
   nlink BEFORE mode, a pad after gid, three reserved longs at the end).
   crtl fills it by field name from its own bridge record, so the order is
   free for crtl's own programs -- but an --emit-obj --system-libs object
   hands it to the HOST libc's fstat/stat/lstat, which write 144 bytes in
   glibc's order: in crtl's former 120-byte order (mode at 16, nlink at 24)
   that was a stack overrun and every field after st_ino wrong. Found linking
   pxx-built wlroots against glibc. struct stat64 is the same struct there.
   Other targets keep crtl's order until each is matched to its libc
   (feature-crtl-struct-stat-is-the-host-libc-layout-on-every-target).
   bug-crtl-struct-stat-is-not-glibc-s-layout-on-x86-64 */
struct stat {
  dev_t     st_dev;
  ino_t     st_ino;
  nlink_t   st_nlink;
  mode_t    st_mode;
  uid_t     st_uid;
  gid_t     st_gid;
  int       __pad0;
  dev_t     st_rdev;
  off_t     st_size;
  blksize_t st_blksize;
  blkcnt_t  st_blocks;
  struct timespec st_atim;
  struct timespec st_mtim;
  struct timespec st_ctim;
  long      __glibc_reserved[3];
};
struct stat64 {
  dev_t     st_dev;
  ino64_t   st_ino;
  nlink_t   st_nlink;
  mode_t    st_mode;
  uid_t     st_uid;
  gid_t     st_gid;
  int       __pad0;
  dev_t     st_rdev;
  off64_t   st_size;
  blksize_t st_blksize;
  blkcnt64_t st_blocks;
  struct timespec st_atim;
  struct timespec st_mtim;
  struct timespec st_ctim;
  long      __glibc_reserved[3];
};
#else
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
  /* POSIX 2008 timestamps, with glibc's macros for the old second-only
     names. busybox stat reads st_atim; with only st_atime here the member
     check refused it (before 2026-09-24 it read offset 0 instead). */
  struct timespec st_atim;
  struct timespec st_mtim;
  struct timespec st_ctim;
};
/* struct stat with a 64-bit st_size on every target: the same layout as
   struct stat on LP64, wider on ILP32 (where off_t is 32 bits). dev_t, ino_t
   and blkcnt_t are already 64-bit. feature-crtl-runtime-gaps-from-e2fsprogs-util-linux-dosfstools */
struct stat64 {
  dev_t     st_dev;
  ino64_t   st_ino;
  mode_t    st_mode;
  nlink_t   st_nlink;
  uid_t     st_uid;
  gid_t     st_gid;
  dev_t     st_rdev;
  off64_t   st_size;
  blksize_t st_blksize;
  blkcnt64_t st_blocks;
  struct timespec st_atim;
  struct timespec st_mtim;
  struct timespec st_ctim;
};
#endif
extern int stat64(const char *path, struct stat64 *buf);
extern int fstat64(int fd, struct stat64 *buf);
extern int lstat64(const char *path, struct stat64 *buf);
extern int fstatat64(int dirfd, const char *path, struct stat64 *buf, int flags);

#define st_atime st_atim.tv_sec
#define st_mtime st_mtim.tv_sec
#define st_ctime st_ctim.tv_sec

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
extern int mknod(const char *path, mode_t mode, dev_t dev);
extern int mkfifo(const char *path, mode_t mode);
extern int fchmod(int fd, mode_t mode);
extern mode_t umask(mode_t mask);

/* The directory-relative family. dirfd is an open directory or AT_FDCWD, and
   flags take AT_SYMLINK_NOFOLLOW / AT_EMPTY_PATH (from <fcntl.h>). A tree
   walker that holds directory descriptors -- toybox's dirtree, find, rm -r,
   cp -r -- resolves every name through these, so a version that accepted only
   AT_FDCWD would look right in a test run from the top directory and stat the
   wrong file one level down. */
extern int fstatat(int dirfd, const char *path, struct stat *buf, int flags);
extern int fchmodat(int dirfd, const char *path, mode_t mode, int flags);
extern int mkdirat(int dirfd, const char *path, mode_t mode);
extern int mknodat(int dirfd, const char *path, mode_t mode, dev_t dev);
extern int mkfifoat(int dirfd, const char *path, mode_t mode);

/* statx(2), GNU: struct statx from <linux/stat.h>, as glibc's <sys/stat.h>
   provides it under _GNU_SOURCE. feature-crtl-statx-file-handle-open-how */
#ifdef _GNU_SOURCE
#include <linux/stat.h>
extern int statx(int dirfd, const char *path, int flags, unsigned int mask, struct statx *buf);
#endif

#endif
