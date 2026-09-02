/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <sys/swap.h> -- swapon(2) and swapoff(2).
 *
 * SWAP_FLAG_PREFER CARRIES A PRIORITY IN ITS LOW BITS, which is why the mask
 * and the shift are here and not left to the caller to remember: the priority
 * goes in bits 0..14 of the same int as the flags, and busybox's
 * util-linux/swaponoff.c builds it that way.
 *
 * Found attempting busybox on i386.
 * feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_SYS_SWAP_H
#define _CRTL_SYS_SWAP_H

#define SWAP_FLAG_PREFER      0x8000   /* the priority below is meaningful */
#define SWAP_FLAG_PRIO_MASK   0x7fff
#define SWAP_FLAG_PRIO_SHIFT  0
#define SWAP_FLAG_DISCARD     0x10000

int swapon(const char *path, int swapflags);
int swapoff(const char *path);

#endif
