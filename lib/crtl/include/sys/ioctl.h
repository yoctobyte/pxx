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

/* The _IOC request-encoding family (asm-generic/ioctl.h). glibc's <sys/ioctl.h>
   reaches these through <bits/ioctls.h> -> <asm/ioctl.h>, and real programs
   spell their own ioctl numbers with them rather than including a linux/ uapi
   header: busybox writes `#define FDGETPRM _IOR(2, 0x04, struct floppy_struct)`
   and `_IOW(BTRFS_IOCTL_MAGIC, 9, int)` directly. Without them the macro name
   survives preprocessing as a call with a TYPE for an argument, which is not a
   C expression at all — the diagnostic lands on `_IOR`, far from the header
   that should have supplied it.

   The layout below is asm-generic's, which every target pxx builds for
   (x86_64, aarch64, arm32, riscv32/64, xtensa) uses; only mips, alpha, sparc,
   parisc and powerpc encode differently, and pxx targets none of them. This is
   the same reasoning the TCGETS constant above rests on.

   _IOC_TYPECHECK is the USER-SPACE spelling: the kernel's variant compares
   sizeof(t) against sizeof(t[1]) to provoke an error when t is not a type, but
   that arm is #ifdef __KERNEL__ and yields the identical value here. */

#include <stddef.h>

#define _IOC_NRBITS    8
#define _IOC_TYPEBITS  8
#define _IOC_SIZEBITS  14
#define _IOC_DIRBITS   2

#define _IOC_NRMASK    ((1 << _IOC_NRBITS) - 1)
#define _IOC_TYPEMASK  ((1 << _IOC_TYPEBITS) - 1)
#define _IOC_SIZEMASK  ((1 << _IOC_SIZEBITS) - 1)
#define _IOC_DIRMASK   ((1 << _IOC_DIRBITS) - 1)

#define _IOC_NRSHIFT   0
#define _IOC_TYPESHIFT (_IOC_NRSHIFT + _IOC_NRBITS)
#define _IOC_SIZESHIFT (_IOC_TYPESHIFT + _IOC_TYPEBITS)
#define _IOC_DIRSHIFT  (_IOC_SIZESHIFT + _IOC_SIZEBITS)

/* Direction is from the APPLICATION's point of view: _IOC_READ means the
   application reads a value the driver wrote. */
#define _IOC_NONE   0U
#define _IOC_WRITE  1U
#define _IOC_READ   2U

#define _IOC(dir, type, nr, size) \
  ((((unsigned int)(dir))  << _IOC_DIRSHIFT)  | \
   (((unsigned int)(type)) << _IOC_TYPESHIFT) | \
   (((unsigned int)(nr))   << _IOC_NRSHIFT)   | \
   (((unsigned int)(size)) << _IOC_SIZESHIFT))

#define _IOC_TYPECHECK(t) (sizeof(t))

#define _IO(type, nr)         _IOC(_IOC_NONE, (type), (nr), 0)
#define _IOR(type, nr, size)  _IOC(_IOC_READ, (type), (nr), (_IOC_TYPECHECK(size)))
#define _IOW(type, nr, size)  _IOC(_IOC_WRITE, (type), (nr), (_IOC_TYPECHECK(size)))
#define _IOWR(type, nr, size) \
  _IOC(_IOC_READ | _IOC_WRITE, (type), (nr), (_IOC_TYPECHECK(size)))

/* Decoding, for code that inspects a request it was handed. */
#define _IOC_DIR(nr)   (((nr) >> _IOC_DIRSHIFT)  & _IOC_DIRMASK)
#define _IOC_TYPE(nr)  (((nr) >> _IOC_TYPESHIFT) & _IOC_TYPEMASK)
#define _IOC_NR(nr)    (((nr) >> _IOC_NRSHIFT)   & _IOC_NRMASK)
#define _IOC_SIZE(nr)  (((nr) >> _IOC_SIZESHIFT) & _IOC_SIZEMASK)

#endif
