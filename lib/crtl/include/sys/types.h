/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_SYS_TYPES_H
#define PXX_CRTL_SYS_TYPES_H 1

#include <stddef.h>
#include <stdint.h>
#include <sys/_types.h>

typedef __off_t off_t;
typedef __ssize_t ssize_t;

/* caddr_t: the BSD "core address" typedef, `char *'. It survives because
   <sys/ioctl.h> users still spell it -- busybox's networking/ifconfig.c casts
   its ifreq payload through it -- and glibc still publishes it from here.
   char*, not void*: the whole point of the older name was pointer arithmetic,
   and a program that does `p + n' on it must keep compiling. */
typedef char *caddr_t;
typedef __time_t time_t;
/* pid_t IS `int', NOT `long', and it does not follow the word size. glibc,
   POSIX and the kernel all agree -- __kernel_pid_t is `int' on every Linux
   architecture -- and this said `long' until 2026-09-02 with no comment saying
   why, which is the tell that it was a default rather than a decision.

   IT ONLY MATTERS IN A STRUCT, which is why it survived: as an argument or a
   return value the extra four bytes are invisible, and `printf("%d", getpid())'
   reads the right half of an over-wide vararg slot on a little-endian machine.
   It was caught by <sys/shm.h>: struct shmid_ds has shm_cpid and shm_lpid, the
   kernel writes 32 bits into each, and an 8-byte pid_t put shm_nattch four
   bytes past where shmctl(IPC_STAT) fills it -- measured against glibc,
   offset 88 against 84 on x86-64. */
typedef int pid_t;
typedef unsigned int mode_t;
typedef unsigned int uid_t;
typedef unsigned int gid_t;
/* id_t is POSIX's "wide enough for any of pid_t, uid_t, gid_t" id -- it is the
   `who' argument of get/setpriority, where the same slot holds a pid, a pgrp
   or a uid depending on `which'. glibc spells it `unsigned int'. */
typedef unsigned int id_t;

/* __daddr_t: the BSD "disk address", a 32-bit `int' on x86-64 AND on i386 --
   glibc spells it __S32_TYPE on both, so it does NOT follow the word size the
   way off_t does. It survives in exactly one place crtl cares about, struct
   mtget's mt_fileno/mt_blkno in <sys/mtio.h>; making it `long' to match its
   neighbours there compiles and changes sizeof(struct mtget), which is encoded
   in MTIOCGET's ioctl number. */
typedef int __daddr_t;
typedef __daddr_t daddr_t;
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

/* loff_t IS `long long' ON EVERY ARCHITECTURE and must not be spelled `long'
   or `off_t'. It is the kernel's 64-bit file offset -- <linux/types.h> here
   already says `typedef long long __kernel_loff_t' for the same reason, and
   mtd-abi.h:14 records that MEMGETBADBLOCK's argument type is baked into the
   ioctl NUMBER through _IOW's size field. Spelling it `long' would compile
   everywhere and make that ioctl read half its argument on every ILP32 target.

   It was MISSING until 2026-09-04, and the cost was not one refusal but three
   error shapes with no shared vocabulary, filed as two separate tickets by two
   sessions. In busybox, `loff_t offs;` is then not a declaration at all: the
   name becomes an undeclared identifier treated as 0, and so does the variable
   it was meant to declare. flash_eraseall.c reported
   `IR_UNSUPPORTED: could not lower AST node (kind 1)' -- &offs was the address
   of an integer LITERAL -- and nandwrite.c reported `undeclared identifier
   passed as argument 3 of bb_xioctl'. Only the quiet
   `warning: undeclared identifier 'loff_t' used as value (treated as 0)'
   named the cause, and it sat directly above an error blaming the frontend.
   One typedef clears both TUs. */
typedef long long loff_t;

/* <sys/select.h> AT THE END, as glibc's <sys/types.h> does (line 179 of the
   host's copy). fd_set and the FD_* macros are reached that way far more often
   than by including <sys/select.h> directly -- busybox's telnetd.c gets them
   through libbb.h and nothing else, and it failed with
   `call to undeclared function: FD_ZERO' after <sys/select.h> already existed
   here, because nobody includes it by name.

   LAST, and not at the top: <sys/select.h> needs the typedefs above (and pulls
   <sys/time.h>), so it has to see a finished file. Both headers are
   guard-wrapped, so the cycle terminates. */
#include <sys/select.h>

#endif
