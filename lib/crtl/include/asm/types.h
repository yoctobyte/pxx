/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <asm/types.h> -- the kernel's fixed-width integer names.
 *
 * SEPARATE FROM <linux/types.h> because UAPI headers include whichever of the
 * two they happen to need, and busybox's networking/libiproute reaches this
 * one directly. Splitting them the way the kernel does costs one file and
 * removes the question.
 *
 * These are exactly uintN_t and intN_t: crtl builds only for targets where
 * `char' is 8 bits and the widths are the obvious ones, so there is no
 * per-architecture arm to get wrong. The file is named `asm/' because the
 * kernel's is; nothing in it is architecture-specific.
 *
 * Found attempting busybox on i386.
 * feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_ASM_TYPES_H
#define _CRTL_ASM_TYPES_H

#include <stdint.h>

typedef int8_t   __s8;
typedef uint8_t  __u8;
typedef int16_t  __s16;
typedef uint16_t __u16;
typedef int32_t  __s32;
typedef uint32_t __u32;
typedef int64_t  __s64;
typedef uint64_t __u64;

#endif
