/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <linux/types.h> -- the kernel's fixed-width spellings.
 *
 * A PARTIAL SHADOW, for the reason <linux/fs.h> gives: a cross target has no
 * host UAPI tree, so "the kernel's to ship" becomes "nobody's". This one is
 * pure typedefs and carries no ABI decision of its own -- __u32 is uint32_t on
 * every target crtl builds for, and the __le/__be aliases are annotations the
 * kernel's sparse checker reads, not distinct types.
 *
 * __kernel_* are the names UAPI headers use for the types the SYSCALL
 * interface passes, which is why they are here rather than in <sys/types.h>:
 * they follow the kernel's width for the target, not the C library's.
 *
 * Found attempting busybox on i386: 3 translation units (watchdog, ip,
 * libiproute/utils) stop at this include.
 * feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_LINUX_TYPES_H
#define _CRTL_LINUX_TYPES_H

#include <stdint.h>
#include <asm/types.h>

typedef uint16_t __le16;
typedef uint16_t __be16;
typedef uint32_t __le32;
typedef uint32_t __be32;
typedef uint64_t __le64;
typedef uint64_t __be64;

typedef uint16_t __sum16;
typedef uint32_t __wsum;

typedef int          __kernel_pid_t;
typedef unsigned int __kernel_uid32_t;
typedef unsigned int __kernel_gid32_t;
typedef long         __kernel_off_t;
typedef long long    __kernel_loff_t;
typedef long         __kernel_time_t;
typedef long         __kernel_suseconds_t;
typedef long         __kernel_clock_t;
typedef unsigned int __kernel_mode_t;

#endif
