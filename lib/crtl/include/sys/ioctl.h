/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_SYS_IOCTL_H
#define PXX_CRTL_SYS_IOCTL_H 1

/* Minimal ioctl surface (sqlite's unix VFS wants the declaration). Implemented
   in src/sys/ioctl.c over the general PalIoctl syscall bridge. */

extern int ioctl(int fd, unsigned long request, ...);
extern int __pxx_ioctl(int fd, long request, void *argp);

/* TCGETS is 0x5401 on every target pxx builds for (asm-generic/ioctls.h; only
   mips/alpha/sparc/powerpc differ) — the same constant __pxx_isatty uses. */
#define TCGETS  0x5401
#define FIONREAD 0x541B

#endif
