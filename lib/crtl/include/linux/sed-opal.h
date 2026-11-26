/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <linux/sed-opal.h> -- only IOC_OPAL_GET_STATUS and what it
 * answers. libblkid asks it when a read fails, so that a self-encrypting
 * disk that is still LOCKED is reported as locked rather than as a disk with
 * nothing on it. The rest of the header (the key, lock and MBR management
 * requests) is sedutil's business and is not here.
 *
 * A PARTIAL SHADOW of the kernel UAPI header (see <linux/fs.h>); values and
 * layouts compared with gcc by test/c_crtl_util_linux_uapi.c.
 */
#ifndef _CRTL_LINUX_SED_OPAL_H
#define _CRTL_LINUX_SED_OPAL_H
#include <linux/types.h>
#include <linux/ioctl.h>

#define OPAL_FL_SUPPORTED         0x00000001
#define OPAL_FL_LOCKING_SUPPORTED 0x00000002
#define OPAL_FL_LOCKING_ENABLED   0x00000004
#define OPAL_FL_LOCKED            0x00000008
#define OPAL_FL_MBR_ENABLED       0x00000010
#define OPAL_FL_MBR_DONE          0x00000020
#define OPAL_FL_SUM_SUPPORTED     0x00000040

struct opal_status {
  __u32 flags;
  __u32 reserved;
};

#define IOC_OPAL_GET_STATUS _IOR('p', 236, struct opal_status)

#endif
