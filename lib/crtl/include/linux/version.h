/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <linux/version.h>.
 *
 * LINUX_VERSION_CODE DESCRIBES THE HEADERS, NOT THE RUNNING KERNEL, and that
 * is true of the kernel's own copy too: a header package built for 6.1 says
 * 6.1 on a box running anything. Programs use it as a proxy for "is this
 * definition present in the uapi I am compiling against", which is a question
 * about crtl's include tree and nothing else -- busybox's iproute.c says so in
 * as many words: "RTA_TABLE is not a define, can't test with ifdef. As a
 * proxy, test which kernels toolchain expects".
 *
 * So the number below is a claim about CRTL, and it is deliberately not read
 * from this box: a value taken from /usr/include would make every build depend
 * on whichever kernel headers happen to be installed, and would answer
 * correctly about the wrong tree. 6.1.0 is the vintage crtl's linux/ headers
 * are transcribed from.
 *
 * RAISING IT IS A PROMISE. A program that takes a newer arm on the strength of
 * this number then names a definition; if crtl has not got it, the failure is
 * a hard "undeclared identifier" and not a wrong answer, which is the only
 * reason a subset can advertise a version at all.
 *
 * Found attempting busybox on i386: libbb/loop.c, libiproute/iproute.c,
 * libiproute/iprule.c.
 * feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_LINUX_VERSION_H
#define _CRTL_LINUX_VERSION_H

#define KERNEL_VERSION(a,b,c) (((a) << 16) + ((b) << 8) + ((c) > 255 ? 255 : (c)))

#define LINUX_VERSION_MAJOR       6
#define LINUX_VERSION_PATCHLEVEL  1
#define LINUX_VERSION_SUBLEVEL    0
#define LINUX_VERSION_CODE        KERNEL_VERSION(6, 1, 0)

#endif
