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

/* __kernel_old_dev_t HAS THREE DIFFERENT WIDTHS and the name says nothing
   about which: `unsigned long' on x86-64 (asm/posix_types_64.h), `unsigned
   short' on i386 (posix_types_32.h), and `unsigned int' for everyone falling
   through to asm-generic. It is the pre-2.6 device number and survives only
   because `struct loop_info' -- the 32-bit LOOP_GET_STATUS -- has two of them.
   Getting it wrong does not fail: on x86-64 a 16-bit version moves lo_inode
   and everything after it, and the ioctl returns a backing inode read out of
   the middle of the struct. Measured against this box's headers, 2026-09-02:
   sizeof(struct loop_info) is 168 with the right width and 160 with the
   short. */
#if defined(__x86_64__)
typedef unsigned long  __kernel_old_dev_t;
#elif defined(__i386__)
typedef unsigned short __kernel_old_dev_t;
#else
typedef unsigned int   __kernel_old_dev_t;
#endif

#endif
