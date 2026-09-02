/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <sys/vfs.h> -- the older spelling of <sys/statfs.h>.
 *
 * ONE LINE ON PURPOSE. glibc's <sys/vfs.h> is `#include <sys/statfs.h>' and
 * nothing else, and crtl already has the real one. Copying struct statfs here
 * would be a second definition of a layout the kernel fixes, and the second
 * copy is the one that drifts -- see <netinet/if_ether.h> for the same
 * reasoning applied to a wire format.
 *
 * Found attempting busybox on i386: util-linux/switch_root.c includes this
 * spelling and reads stfs.f_type against RAMFS_MAGIC.
 * feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_SYS_VFS_H
#define _CRTL_SYS_VFS_H

#include <sys/statfs.h>

#endif
