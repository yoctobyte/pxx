/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_SYS_VT_H
#define PXX_CRTL_SYS_VT_H 1

/* <sys/vt.h> is glibc's name for the kernel's <linux/vt.h>; it has no content
   of its own. crtl's <linux/vt.h> already carries VT_GETMODE, VT_SETMODE,
   VT_PROCESS, VT_ACKACQ, VT_RELDISP and struct vt_mode, which is the whole of
   what busybox's loginutils/vlock.c asks for. */
#include <linux/vt.h>

#endif
