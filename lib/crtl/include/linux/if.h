/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_LINUX_IF_H
#define PXX_CRTL_LINUX_IF_H 1

/* <linux/if.h> IS THE KERNEL UAPI SPELLING OF <net/if.h>, and everything the
   tree needs from it is already there: IFNAMSIZ, the IFF_* flags, and struct
   ifreq with its ifr_* accessor macros. This header exists because real code
   asks for the kernel name -- busybox's ether-wake.c, ifenslave.c and
   ifplugd.c all do -- and a missing header is a hard refusal on every CROSS
   target while resolving silently from /usr/include on the native one.

   Under glibc these two headers famously COLLIDE: both define struct ifreq and
   the IFF_ enum, so including both in one TU is a documented error. Here they
   are one file behind two names, which cannot collide with itself. That is the
   accept-more direction -- a program that includes both compiles, where glibc
   would reject it -- and no correct program can tell the difference. */
#include <net/if.h>

#endif
