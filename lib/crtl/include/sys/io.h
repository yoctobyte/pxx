/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <sys/io.h> -- x86 I/O-port permissions, iopl(2) and ioperm(2).
 * Xorg's Linux support (os-support/linux/lnx_video.c) asks for them before
 * touching VGA ports; with modesetting it never needs the ports, and a
 * refusal is what it handles. Other targets have neither call: -1, ENOSYS.
 *
 * glibc's version also has inb/outb and friends as inline assembly. They
 * are not here; Xorg brings its own (hw/xfree86/common/compiler.h).
 */
#ifndef PXX_CRTL_SYS_IO_H
#define PXX_CRTL_SYS_IO_H 1

int iopl(int level);
int ioperm(unsigned long from, unsigned long num, int turn_on);

#endif
