/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <sys/statfs.h> -- struct statfs and the mount-flag bits.
 *
 * THE LAYOUT WAS THE OPEN QUESTION AND IT IS NOW MEASURED (2026-09-02). This
 * header used to say the struct below was "the 64-bit kernel's" and was "the
 * WRONG one" on 32-bit targets, and asked whoever added the syscall to pick a
 * layout with a differential in hand. The differential says the comment was
 * wrong and the declaration was already right: it is written in `long' and
 * `unsigned long', so it tracks the target's word size, which is precisely how
 * the kernel defines __statfs_word. sizeof and every offsetof, compared
 * against glibc:
 *
 *     x86-64   size 120, f_blocks at 16, f_namelen at 64   (pxx == gcc, byte for byte)
 *     i386     size  64, f_blocks at  8, f_namelen at 36   (pxx == gcc -m32)
 *
 * statfs() and fstatfs() live in src/sys/statfs.c and go over the raw syscall
 * bridge rather than a PAL entry, for the reason src/sys/sysinfo.c gives: the
 * struct is the kernel's own and a PAL entry would be a Linux layout wearing a
 * portable name. Read that file before changing this one -- riscv32 has no
 * plain statfs syscall at all and takes a different path.
 */
#ifndef _CRTL_SYS_STATFS_H
#define _CRTL_SYS_STATFS_H

#include <sys/types.h>

typedef struct { int val[2]; } fsid_t;

struct statfs {
  long   f_type;     /* filesystem magic */
  long   f_bsize;    /* optimal transfer block size */
  unsigned long f_blocks;  /* total data blocks */
  unsigned long f_bfree;   /* free blocks */
  unsigned long f_bavail;  /* free blocks available to unprivileged users */
  unsigned long f_files;   /* total inodes */
  unsigned long f_ffree;   /* free inodes */
  fsid_t f_fsid;
  long   f_namelen;  /* maximum filename length */
  long   f_frsize;   /* fragment size */
  long   f_flags;
  long   f_spare[4];
};

/* Mount flags reported in f_flags (linux/statfs.h). */
#define ST_RDONLY       0x0001
#define ST_NOSUID       0x0002
#define ST_NODEV        0x0004
#define ST_NOEXEC       0x0008
#define ST_SYNCHRONOUS  0x0010
#define ST_VALID        0x0020
#define ST_MANDLOCK     0x0040
#define ST_NOATIME      0x0400
#define ST_NODIRATIME   0x0800
#define ST_RELATIME     0x1000

int statfs(const char *path, struct statfs *buf);
int fstatfs(int fd, struct statfs *buf);

#endif
