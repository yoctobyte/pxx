/* SPDX-License-Identifier: Zlib */
/* <linux/unistd.h>: the kernel uapi header whose job is the __NR_* syscall
   numbers (it includes <asm/unistd.h>). crtl keeps those, per target, in
   <sys/syscall.h>. e2fsprogs' lib/ext2fs/llseek.c includes it for
   __NR__llseek; a hostless target (the Nodisx on-site build inside
   Rainyday) had no header to give it. feature-crtl-the-headers-a-hostless-target-lacks */
#ifndef _LINUX_UNISTD_H
#define _LINUX_UNISTD_H
#include <sys/syscall.h>
#endif
