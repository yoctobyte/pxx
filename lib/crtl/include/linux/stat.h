/* SPDX-License-Identifier: Zlib */
/*
 * <linux/stat.h>: struct statx and its mask/attribute bits, the Linux UAPI
 * layout as statx(2) documents it (one layout on every architecture, 256
 * bytes). crtl's <sys/stat.h> includes it under _GNU_SOURCE, as glibc's
 * does, and declares statx(). Guarded like the kernel's own header, so a
 * unit that includes both spellings sees one definition.
 * feature-crtl-statx-file-handle-open-how
 */
#ifndef _LINUX_STAT_H
#define _LINUX_STAT_H 1

#include <linux/types.h>

struct statx_timestamp {
  __s64 tv_sec;
  __u32 tv_nsec;
  __s32 __reserved;
};

struct statx {
  __u32 stx_mask;
  __u32 stx_blksize;
  __u64 stx_attributes;
  __u32 stx_nlink;
  __u32 stx_uid;
  __u32 stx_gid;
  __u16 stx_mode;
  __u16 __spare0[1];
  __u64 stx_ino;
  __u64 stx_size;
  __u64 stx_blocks;
  __u64 stx_attributes_mask;
  struct statx_timestamp stx_atime;
  struct statx_timestamp stx_btime;
  struct statx_timestamp stx_ctime;
  struct statx_timestamp stx_mtime;
  __u32 stx_rdev_major;
  __u32 stx_rdev_minor;
  __u32 stx_dev_major;
  __u32 stx_dev_minor;
  __u64 stx_mnt_id;
  __u32 stx_dio_mem_align;
  __u32 stx_dio_offset_align;
  __u64 stx_subvol;
  __u32 stx_atomic_write_unit_min;
  __u32 stx_atomic_write_unit_max;
  __u32 stx_atomic_write_segments_max;
  __u32 stx_dio_read_offset_align;
  __u32 stx_atomic_write_unit_max_opt;
  __u32 __spare2[1];
  __u64 __spare3[8];
};

#define STATX_TYPE            0x00000001U
#define STATX_MODE            0x00000002U
#define STATX_NLINK           0x00000004U
#define STATX_UID             0x00000008U
#define STATX_GID             0x00000010U
#define STATX_ATIME           0x00000020U
#define STATX_MTIME           0x00000040U
#define STATX_CTIME           0x00000080U
#define STATX_INO             0x00000100U
#define STATX_SIZE            0x00000200U
#define STATX_BLOCKS          0x00000400U
#define STATX_BASIC_STATS     0x000007ffU
#define STATX_BTIME           0x00000800U
#define STATX_MNT_ID          0x00001000U
#define STATX_DIOALIGN        0x00002000U
#define STATX_MNT_ID_UNIQUE   0x00004000U
#define STATX_SUBVOL          0x00008000U
#define STATX_WRITE_ATOMIC    0x00010000U
#define STATX_DIO_READ_ALIGN  0x00020000U
#define STATX__RESERVED       0x80000000U
#define STATX_ALL             0x00000fffU

#define STATX_ATTR_COMPRESSED    0x00000004
#define STATX_ATTR_IMMUTABLE     0x00000010
#define STATX_ATTR_APPEND        0x00000020
#define STATX_ATTR_NODUMP        0x00000040
#define STATX_ATTR_ENCRYPTED     0x00000800
#define STATX_ATTR_AUTOMOUNT     0x00001000
#define STATX_ATTR_MOUNT_ROOT    0x00002000
#define STATX_ATTR_VERITY        0x00100000
#define STATX_ATTR_DAX           0x00200000
#define STATX_ATTR_WRITE_ATOMIC  0x00400000

#endif
