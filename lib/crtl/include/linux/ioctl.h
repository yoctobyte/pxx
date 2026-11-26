/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <linux/ioctl.h> -- the _IO/_IOR/_IOW/_IOWR encoders, as the
 * kernel's header has them: it is nothing but <asm/ioctl.h>, which every pxx
 * target takes from the generic encoding. util-linux includes it ahead of
 * <linux/blkzoned.h> and <linux/blkpg.h>.
 */
#ifndef _CRTL_LINUX_IOCTL_H
#define _CRTL_LINUX_IOCTL_H
#include <asm/ioctl.h>
#endif
