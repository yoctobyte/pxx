/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <linux/bpf_common.h> -- the classic-BPF instruction encoding.
 *
 * EVERY VALUE HERE IS ZERO IN SOME FIELD. BPF_LD, BPF_W, BPF_IMM, BPF_ADD,
 * BPF_JA and BPF_K are all 0x00, and BPF_LDX, BPF_H and BPF_X are all 0x08 --
 * they are not alternatives, they are values of DIFFERENT bitfields inside one
 * 16-bit opcode, and the accessor macros (BPF_CLASS, BPF_SIZE, BPF_MODE,
 * BPF_OP, BPF_SRC) are what say which field a number belongs to. A name copied
 * from the wrong group therefore assembles a legal instruction with a
 * different meaning: BPF_JMP|BPF_JGT where BPF_JGE was meant drops the packet
 * on the boundary case only, so the filter works in testing and loses one
 * packet in a thousand.
 *
 * That is also why this is a separate header rather than being folded into
 * <linux/filter.h>: the kernel splits them, and the split is the line between
 * "the instruction encoding" and "the socket-filter interface".
 *
 * Found attempting busybox on i386, via <linux/filter.h>:
 * networking/udhcp/dhcpc.c and d6_dhcpc.c.
 * feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_LINUX_BPF_COMMON_H
#define _CRTL_LINUX_BPF_COMMON_H

/* Instruction classes. */
#define BPF_CLASS(code) ((code) & 0x07)
#define BPF_LD    0x00
#define BPF_LDX   0x01
#define BPF_ST    0x02
#define BPF_STX   0x03
#define BPF_ALU   0x04
#define BPF_JMP   0x05
#define BPF_RET   0x06
#define BPF_MISC  0x07

/* ld/ldx fields: size. */
#define BPF_SIZE(code) ((code) & 0x18)
#define BPF_W  0x00   /* 32-bit */
#define BPF_H  0x08   /* 16-bit */
#define BPF_B  0x10   /*  8-bit */

/* ld/ldx fields: mode. */
#define BPF_MODE(code) ((code) & 0xe0)
#define BPF_IMM  0x00
#define BPF_ABS  0x20
#define BPF_IND  0x40
#define BPF_MEM  0x60
#define BPF_LEN  0x80
#define BPF_MSH  0xa0

/* alu/jmp fields. */
#define BPF_OP(code) ((code) & 0xf0)
#define BPF_ADD  0x00
#define BPF_SUB  0x10
#define BPF_MUL  0x20
#define BPF_DIV  0x30
#define BPF_OR   0x40
#define BPF_AND  0x50
#define BPF_LSH  0x60
#define BPF_RSH  0x70
#define BPF_NEG  0x80
#define BPF_MOD  0x90
#define BPF_XOR  0xa0

#define BPF_JA    0x00
#define BPF_JEQ   0x10
#define BPF_JGT   0x20
#define BPF_JGE   0x30
#define BPF_JSET  0x40

#define BPF_SRC(code) ((code) & 0x08)
#define BPF_K  0x00
#define BPF_X  0x08

#ifndef BPF_MAXINSNS
#define BPF_MAXINSNS 4096
#endif

#endif
