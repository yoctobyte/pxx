/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <linux/nbd.h> -- the network block device ioctls.
 *
 * Written for pxx from the kernel's documented ABI (the numbers are the ABI,
 * checked against a gcc build over the system header on x86-64 and i386);
 * only what userland tools reach. Without it a native x86-64 build silently
 * took the HOST's copy and every cross target failed to find one.
 * Found building toybox (feature-c-toybox-builds-with-pxx).
 */
#ifndef PXX_CRTL_LINUX_NBD_H
#define PXX_CRTL_LINUX_NBD_H 1

#include <sys/ioctl.h>

#define NBD_SET_SOCK        _IO(0xab, 0)
#define NBD_SET_BLKSIZE     _IO(0xab, 1)
#define NBD_SET_SIZE        _IO(0xab, 2)
#define NBD_DO_IT           _IO(0xab, 3)
#define NBD_CLEAR_SOCK      _IO(0xab, 4)
#define NBD_CLEAR_QUE       _IO(0xab, 5)
#define NBD_PRINT_DEBUG     _IO(0xab, 6)
#define NBD_SET_SIZE_BLOCKS _IO(0xab, 7)
#define NBD_DISCONNECT      _IO(0xab, 8)
#define NBD_SET_TIMEOUT     _IO(0xab, 9)
#define NBD_SET_FLAGS       _IO(0xab, 10)

#endif
