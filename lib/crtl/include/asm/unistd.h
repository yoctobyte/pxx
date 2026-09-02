/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <asm/unistd.h>.
 *
 * A FORWARDER TO <sys/syscall.h>, WHICH IS WHERE crtl KEEPS BOTH SPELLINGS.
 * The kernel's arrangement is the other way round -- asm/unistd.h has the
 * __NR_* numbers and sys/syscall.h wraps them as SYS_* -- but crtl's
 * <sys/syscall.h> already carries the per-architecture __NR_ table because the
 * SYS_ names are defined in terms of it, so this header exists to answer the
 * INCLUDE, not to define anything. Splitting the table in two so the arrow
 * could run the kernel's way would give six architectures' worth of syscall
 * numbers a second definition site, and a syscall number that disagrees with
 * itself does not fail: it calls something else.
 *
 * Found attempting busybox on i386: util-linux/ionice.c, which includes both
 * spellings and then uses SYS_ioprio_set.
 * feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_ASM_UNISTD_H
#define _CRTL_ASM_UNISTD_H

#include <sys/syscall.h>

#endif
