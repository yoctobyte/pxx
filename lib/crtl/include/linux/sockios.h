/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <linux/sockios.h>.
 *
 * THE NUMBERS ARE IN <sys/ioctl.h> AND THIS HEADER FORWARDS TO THEM. glibc
 * runs the arrow the other way -- bits/ioctls.h includes this file -- but the
 * direction is not what matters; having ONE definition site is. Two copies of
 * 77 socket ioctls do not fail to compile, they fail when one is edited, and a
 * SIOCGIF* off by a digit fills a different part of `struct ifreq' while the
 * caller prints a plausible address.
 *
 * Programs include either spelling and must get the same numbers: busybox's
 * ifconfig.c takes <sys/ioctl.h>, brctl.c and ifenslave.c take this one.
 *
 * Found attempting busybox on i386: networking/brctl.c, ifenslave.c,
 * ifplugd.c, zcip.c, nameif.c.
 * feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_LINUX_SOCKIOS_H
#define _CRTL_LINUX_SOCKIOS_H

#include <sys/ioctl.h>

#endif
