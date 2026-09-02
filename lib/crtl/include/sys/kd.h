/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <sys/kd.h>.
 *
 * A FORWARDER TO <linux/kd.h>, which is exactly what glibc's copy is. glibc
 * wraps it in an undef dance around _LINUX_TYPES_H so the kernel header can be
 * included after its own <linux/types.h>; crtl has one <linux/types.h> with a
 * plain guard, so there is nothing to undo.
 *
 * Found attempting busybox on i386: console-tools/loadfont.c,
 * miscutils/conspy.c.
 * feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_SYS_KD_H
#define _CRTL_SYS_KD_H

#include <linux/kd.h>

#endif
