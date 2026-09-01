/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_SYS_TYPES_H
#define PXX_CRTL_SYS_TYPES_H 1

#include <stddef.h>
#include <stdint.h>
#include <sys/_types.h>

typedef __off_t off_t;
typedef __ssize_t ssize_t;
typedef __time_t time_t;
typedef long pid_t;
typedef unsigned int mode_t;
typedef unsigned int uid_t;
typedef unsigned int gid_t;
/* dev_t and ino_t are 64-bit in glibc on EVERY target, independent of
   _FILE_OFFSET_BITS, because both carry values the kernel hands out at 64 bits:
   statx returns stx_ino as a u64, and the userspace dev_t encoding that
   <sys/sysmacros.h> implements puts (major & ~0xfff) at bit 32. Spelling them
   `unsigned long` made them 32 bits on every ILP32 target and truncated both.

   dev_t is OBSERVED broken, not merely reasoned: makedev(4096, 1) came back as
   major 0 on i386, arm32 and riscv32 and as 4096 on x86-64 and aarch64, from
   the same source. test/c_stat_rdev_decodes.c carries that row.

   ino_t is the same one-word mistake in the same population and is NOT observed
   here -- the largest inode anywhere on this host is 0xF0000000, which fits an
   unsigned 32-bit field. xfs with inode64 exceeds it routinely; that is the
   argument, and it is an argument, not a measurement. */
typedef unsigned long long dev_t;
typedef unsigned long long ino_t;

#endif
