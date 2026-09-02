/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <sys/statvfs.h> -- the POSIX filesystem-statistics call.
 *
 * statvfs IS NOT A SYSCALL. It is statfs(2) rearranged, and the rearranging is
 * the whole content of src/sys/statvfs.c -- see the mapping there, and in
 * particular f_favail, which POSIX has and Linux does not, so it is f_ffree.
 *
 * `int __f_unused' EXISTS ON 32-BIT AND NOT ON 64-BIT, which is glibc's
 * arrangement and not a choice this header is free to make: it is padding that
 * keeps f_flag 8-aligned where the counts are 64 bits, and on i386 the counts
 * are 32 bits and the hole is explicit instead. Getting it wrong does not fail
 * -- every field after f_fsid moves by four bytes, and df prints a mount flag
 * where the maximum filename length should be. Measured against glibc,
 * 2026-09-02: 112 bytes on x86-64 and 72 on i386.
 *
 * THE COUNTS ARE `unsigned long', SO THEY ARE 32 BITS ON i386, which caps
 * f_blocks at 16TB there for a 4K block size. That is glibc's default too (its
 * 64-bit arm is __USE_FILE_OFFSET64, a feature-test macro crtl does not
 * implement), and it matches what <sys/statfs.h> already does with the same
 * fields for the same reason. A program that wants the wide answer on a 32-bit
 * target should be reading statfs64, which is a different interface.
 *
 * Found attempting busybox on i386: coreutils/df.c.
 * feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_SYS_STATVFS_H
#define _CRTL_SYS_STATVFS_H

#include <sys/types.h>
#include <sys/statfs.h>   /* fsid_t, and the ST_* flags f_flag reports */

typedef unsigned long fsblkcnt_t;
typedef unsigned long fsfilcnt_t;

struct statvfs {
  unsigned long f_bsize;    /* filesystem block size */
  unsigned long f_frsize;   /* fragment size */
  fsblkcnt_t    f_blocks;   /* size of fs in f_frsize units */
  fsblkcnt_t    f_bfree;    /* free blocks */
  fsblkcnt_t    f_bavail;   /* free blocks for unprivileged users */
  fsfilcnt_t    f_files;    /* inodes */
  fsfilcnt_t    f_ffree;    /* free inodes */
  fsfilcnt_t    f_favail;   /* free inodes for unprivileged users */
  unsigned long f_fsid;
#if !defined(__x86_64__) && !defined(__aarch64__) && !defined(__riscv64) \
    && !(defined(__riscv) && __riscv_xlen == 64)
  int           __f_unused;   /* 32-bit only -- see the note above */
#endif
  unsigned long f_flag;     /* ST_* */
  unsigned long f_namemax;  /* maximum filename length */
  unsigned int  f_type;     /* filesystem magic, as statfs reports it */
  int           __f_spare[5];
};

int statvfs(const char *path, struct statvfs *buf);
int fstatvfs(int fd, struct statvfs *buf);

#endif
