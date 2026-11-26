/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <linux/blkpg.h> -- BLKPG, the ioctl that adds, removes and
 * resizes one partition of a disk in the kernel's view without rereading
 * the whole table. fdisk and sfdisk tell the kernel about the table they
 * wrote with it (libfdisk's fdisk_reread_changes) when BLKRRPART is refused
 * because a partition is in use.
 *
 * A PARTIAL SHADOW of the kernel UAPI header (see <linux/fs.h>); values and
 * layouts compared with gcc by test/c_crtl_util_linux_uapi.c.
 */
#ifndef _CRTL_LINUX_BLKPG_H
#define _CRTL_LINUX_BLKPG_H
#include <linux/ioctl.h>

#define BLKPG _IO(0x12, 105)

struct blkpg_ioctl_arg {
  int op;
  int flags;
  int datalen;
  void *data;
};

#define BLKPG_ADD_PARTITION    1
#define BLKPG_DEL_PARTITION    2
#define BLKPG_RESIZE_PARTITION 3

#define BLKPG_DEVNAMELTH 64
#define BLKPG_VOLNAMELTH 64

struct blkpg_partition {
  long long start;      /* bytes */
  long long length;     /* bytes */
  int pno;
  char devname[BLKPG_DEVNAMELTH];
  char volname[BLKPG_VOLNAMELTH];
};

#endif
