/* SPDX-License-Identifier: Zlib */
/* <linux/falloc.h>: the fallocate(2) mode bits, kernel values. <fcntl.h> has
   the two busybox uses; e2fsprogs' lib/ext2fs/unix_io.c includes this header
   and also passes FALLOC_FL_ZERO_RANGE. The values are the kernel's
   (include/uapi/linux/falloc.h). feature-crtl-the-headers-a-hostless-target-lacks */
#ifndef _LINUX_FALLOC_H
#define _LINUX_FALLOC_H
#ifndef FALLOC_FL_KEEP_SIZE
#define FALLOC_FL_KEEP_SIZE   0x01
#endif
#ifndef FALLOC_FL_PUNCH_HOLE
#define FALLOC_FL_PUNCH_HOLE  0x02
#endif
#define FALLOC_FL_ZERO_RANGE  0x10
#endif
