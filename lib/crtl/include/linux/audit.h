/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <linux/audit.h>, PARTIAL: the AUDIT_ARCH_* values, which name a
 * syscall ABI as the ELF machine number plus a 64-bit and a little-endian bit.
 * A seccomp filter checks seccomp_data.arch against the one it was written
 * for (dhcpcd's privsep-linux.c); seccomp hands them out too. The audit
 * subsystem's netlink messages, rule fields and operators are not here.
 */
#ifndef _CRTL_LINUX_AUDIT_H
#define _CRTL_LINUX_AUDIT_H
#include <linux/types.h>
#include <linux/elf-em.h>

#define AUDIT_ARCH 11   /* the rule field that compares the arch */

#define __AUDIT_ARCH_CONVENTION_MASK       0x30000000
#define __AUDIT_ARCH_CONVENTION_MIPS64_N32 0x20000000
#define __AUDIT_ARCH_64BIT 0x80000000
#define __AUDIT_ARCH_LE    0x40000000

#define AUDIT_ARCH_AARCH64     (EM_AARCH64 | __AUDIT_ARCH_64BIT | __AUDIT_ARCH_LE)
#define AUDIT_ARCH_ALPHA       (EM_ALPHA | __AUDIT_ARCH_64BIT | __AUDIT_ARCH_LE)
#define AUDIT_ARCH_ARCOMPACT   (EM_ARCOMPACT | __AUDIT_ARCH_LE)
#define AUDIT_ARCH_ARCOMPACTBE (EM_ARCOMPACT)
#define AUDIT_ARCH_ARCV2       (EM_ARCV2 | __AUDIT_ARCH_LE)
#define AUDIT_ARCH_ARCV2BE     (EM_ARCV2)
#define AUDIT_ARCH_ARM         (EM_ARM | __AUDIT_ARCH_LE)
#define AUDIT_ARCH_ARMEB       (EM_ARM)
#define AUDIT_ARCH_C6X         (EM_TI_C6000 | __AUDIT_ARCH_LE)
#define AUDIT_ARCH_C6XBE       (EM_TI_C6000)
#define AUDIT_ARCH_CRIS        (EM_CRIS | __AUDIT_ARCH_LE)
#define AUDIT_ARCH_CSKY        (EM_CSKY | __AUDIT_ARCH_LE)
#define AUDIT_ARCH_FRV         (EM_FRV)
#define AUDIT_ARCH_H8300       (EM_H8_300)
#define AUDIT_ARCH_HEXAGON     (EM_HEXAGON)
#define AUDIT_ARCH_I386        (EM_386 | __AUDIT_ARCH_LE)
#define AUDIT_ARCH_IA64        (EM_IA_64 | __AUDIT_ARCH_64BIT | __AUDIT_ARCH_LE)
#define AUDIT_ARCH_M32R        (EM_M32R)
#define AUDIT_ARCH_M68K        (EM_68K)
#define AUDIT_ARCH_MICROBLAZE  (EM_MICROBLAZE)
#define AUDIT_ARCH_MIPS        (EM_MIPS)
#define AUDIT_ARCH_MIPSEL      (EM_MIPS | __AUDIT_ARCH_LE)
#define AUDIT_ARCH_MIPS64      (EM_MIPS | __AUDIT_ARCH_64BIT)
#define AUDIT_ARCH_MIPS64N32   (EM_MIPS | __AUDIT_ARCH_64BIT | __AUDIT_ARCH_CONVENTION_MIPS64_N32)
#define AUDIT_ARCH_MIPSEL64    (EM_MIPS | __AUDIT_ARCH_64BIT | __AUDIT_ARCH_LE)
#define AUDIT_ARCH_MIPSEL64N32 (EM_MIPS | __AUDIT_ARCH_64BIT | __AUDIT_ARCH_LE | __AUDIT_ARCH_CONVENTION_MIPS64_N32)
#define AUDIT_ARCH_NDS32       (EM_NDS32 | __AUDIT_ARCH_LE)
#define AUDIT_ARCH_NDS32BE     (EM_NDS32)
#define AUDIT_ARCH_NIOS2       (EM_ALTERA_NIOS2 | __AUDIT_ARCH_LE)
#define AUDIT_ARCH_OPENRISC    (EM_OPENRISC)
#define AUDIT_ARCH_PARISC      (EM_PARISC)
#define AUDIT_ARCH_PARISC64    (EM_PARISC | __AUDIT_ARCH_64BIT)
#define AUDIT_ARCH_PPC         (EM_PPC)
#define AUDIT_ARCH_PPC64       (EM_PPC64 | __AUDIT_ARCH_64BIT)
#define AUDIT_ARCH_PPC64LE     (EM_PPC64 | __AUDIT_ARCH_64BIT | __AUDIT_ARCH_LE)
#define AUDIT_ARCH_RISCV32     (EM_RISCV | __AUDIT_ARCH_LE)
#define AUDIT_ARCH_RISCV64     (EM_RISCV | __AUDIT_ARCH_64BIT | __AUDIT_ARCH_LE)
#define AUDIT_ARCH_S390        (EM_S390)
#define AUDIT_ARCH_S390X       (EM_S390 | __AUDIT_ARCH_64BIT)
#define AUDIT_ARCH_SH          (EM_SH)
#define AUDIT_ARCH_SHEL        (EM_SH | __AUDIT_ARCH_LE)
#define AUDIT_ARCH_SH64        (EM_SH | __AUDIT_ARCH_64BIT)
#define AUDIT_ARCH_SHEL64      (EM_SH | __AUDIT_ARCH_64BIT | __AUDIT_ARCH_LE)
#define AUDIT_ARCH_SPARC       (EM_SPARC)
#define AUDIT_ARCH_SPARC64     (EM_SPARCV9 | __AUDIT_ARCH_64BIT)
#define AUDIT_ARCH_TILEGX      (EM_TILEGX | __AUDIT_ARCH_64BIT | __AUDIT_ARCH_LE)
#define AUDIT_ARCH_TILEGX32    (EM_TILEGX | __AUDIT_ARCH_LE)
#define AUDIT_ARCH_TILEPRO     (EM_TILEPRO | __AUDIT_ARCH_LE)
#define AUDIT_ARCH_UNICORE     (EM_UNICORE | __AUDIT_ARCH_LE)
#define AUDIT_ARCH_X86_64      (EM_X86_64 | __AUDIT_ARCH_64BIT | __AUDIT_ARCH_LE)
#define AUDIT_ARCH_XTENSA      (EM_XTENSA)
#define AUDIT_ARCH_LOONGARCH32 (EM_LOONGARCH | __AUDIT_ARCH_LE)
#define AUDIT_ARCH_LOONGARCH64 (EM_LOONGARCH | __AUDIT_ARCH_64BIT | __AUDIT_ARCH_LE)

#endif
