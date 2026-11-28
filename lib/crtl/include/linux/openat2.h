/* SPDX-License-Identifier: Zlib */
/*
 * <linux/openat2.h>: struct open_how and the RESOLVE_* bits, the Linux UAPI
 * as openat2(2) documents it. crtl's <fcntl.h> includes it under
 * _GNU_SOURCE, as glibc's does. feature-crtl-statx-file-handle-open-how
 */
#ifndef _LINUX_OPENAT2_H
#define _LINUX_OPENAT2_H 1

#include <linux/types.h>

struct open_how {
  __u64 flags;
  __u64 mode;
  __u64 resolve;
};

#define RESOLVE_NO_XDEV        0x01
#define RESOLVE_NO_MAGICLINKS  0x02
#define RESOLVE_NO_SYMLINKS    0x04
#define RESOLVE_BENEATH        0x08
#define RESOLVE_IN_ROOT        0x10
#define RESOLVE_CACHED         0x20

#endif
