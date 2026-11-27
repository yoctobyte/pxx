/* SPDX-License-Identifier: Zlib */
/* <linux/audit.h>: only the AUDIT_ARCH_* values, which a seccomp filter
   compares against seccomp_data.arch. These are the kernel's numbers
   (EM_* | __AUDIT_ARCH_64BIT | __AUDIT_ARCH_LE), for the architectures pxx
   targets. dhcpcd's privsep-linux.c uses them.
   feature-nodisx-dhcpcd-with-privilege-separation */
#ifndef _LINUX_AUDIT_H
#define _LINUX_AUDIT_H
#define __AUDIT_ARCH_64BIT    0x80000000U
#define __AUDIT_ARCH_LE       0x40000000U
#define AUDIT_ARCH_X86_64     0xC000003EU
#define AUDIT_ARCH_I386       0x40000003U
#define AUDIT_ARCH_AARCH64    0xC00000B7U
#define AUDIT_ARCH_ARM        0x40000028U
#define AUDIT_ARCH_RISCV32    0x400000F3U
#define AUDIT_ARCH_RISCV64    0xC00000F3U
#define AUDIT_ARCH_XTENSA     0x0000005EU
#endif
