/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <sys/statfs.h> -- struct statfs and the mount-flag bits. No
 * statfs()/fstatfs(): the PAL has no entry for either.
 *
 * Same rule as <pwd.h> and <sys/resource.h>, which see for the reasoning --
 * busybox pulls this header into every translation unit from
 * include/libbb.h and calls it only from df/mount. Adding the calls is PAL
 * work, not header work.
 *
 * The layout is the 64-bit kernel's struct statfs, which is what x86-64 and
 * aarch64 pass. On the 32-bit targets the kernel's statfs and statfs64 differ
 * and this is the WRONG one -- deliberately not papered over with an #if,
 * because nothing can fill the struct yet and a fabricated layout that nobody
 * exercises is how a wrong offset gets frozen in. Whoever adds the syscall
 * picks the layout with a differential in hand.
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

#endif
