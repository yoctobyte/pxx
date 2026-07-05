/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_SYS_IOCTL_H
#define PXX_CRTL_SYS_IOCTL_H 1

/* Minimal ioctl declaration for sqlite's unix VFS. Declaration only. */

extern int ioctl(int fd, unsigned long request, ...);

#endif
