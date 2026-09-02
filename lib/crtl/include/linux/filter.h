/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <linux/filter.h> -- the classic socket-filter interface.
 *
 * BPF_STMT AND BPF_JUMP EXPAND TO BRACED INITIALISERS, not to calls. They are
 * only ever written inside a `struct sock_filter[]' initialiser, so a version
 * that returned a value would not fail at the macro -- it would fail at every
 * use site with a syntax error a long way from the cause. The `(unsigned
 * short)' cast on `code' is the kernel's and is load-bearing: the operands are
 * ORed ints and the field is 16 bits.
 *
 * struct sock_fprog's `len' is `unsigned short' and NOT int -- setsockopt hands
 * the whole struct to the kernel, so a widened field puts `filter' at the wrong
 * offset and the kernel reads a filter program from whatever follows.
 *
 * The instruction encoding proper is in <linux/bpf_common.h>, which this
 * includes; see the note there about every value being zero in some field.
 *
 * Found attempting busybox on i386: networking/udhcp/dhcpc.c and d6_dhcpc.c,
 * which attach a filter so the raw socket only wakes them for DHCP replies.
 * feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_LINUX_FILTER_H
#define _CRTL_LINUX_FILTER_H

#include <linux/types.h>
#include <linux/bpf_common.h>

#define BPF_MAJOR_VERSION 1
#define BPF_MINOR_VERSION 1

struct sock_filter {   /* Filter block */
  __u16 code;   /* Actual filter code */
  __u8  jt;     /* Jump true */
  __u8  jf;     /* Jump false */
  __u32 k;      /* Generic multiuse field */
};

struct sock_fprog {    /* Required for SO_ATTACH_FILTER. */
  unsigned short len;  /* Number of filter blocks */
  struct sock_filter *filter;
};

/* ret - BPF_K and BPF_X also apply */
#define BPF_RVAL(code) ((code) & 0x18)
#define BPF_A  0x10

/* misc */
#define BPF_MISCOP(code) ((code) & 0xf8)
#define BPF_TAX  0x00
#define BPF_TXA  0x80

#ifndef BPF_STMT
#define BPF_STMT(code, k) { (unsigned short)(code), 0, 0, k }
#endif
#ifndef BPF_JUMP
#define BPF_JUMP(code, k, jt, jf) { (unsigned short)(code), jt, jf, k }
#endif

#define BPF_MEMWORDS 16

/* Ancillary data, addressed at a NEGATIVE offset so it cannot collide with a
   real packet offset. */
#define SKF_AD_OFF               (-0x1000)
#define SKF_AD_PROTOCOL          0
#define SKF_AD_PKTTYPE           4
#define SKF_AD_IFINDEX           8
#define SKF_AD_NLATTR            12
#define SKF_AD_NLATTR_NEST       16
#define SKF_AD_MARK              20
#define SKF_AD_QUEUE             24
#define SKF_AD_HATYPE            28
#define SKF_AD_RXHASH            32
#define SKF_AD_CPU               36
#define SKF_AD_ALU_XOR_X         40
#define SKF_AD_VLAN_TAG          44
#define SKF_AD_VLAN_TAG_PRESENT  48
#define SKF_AD_PAY_OFFSET        52
#define SKF_AD_RANDOM            56
#define SKF_AD_VLAN_TPID         60
#define SKF_AD_MAX               64

#define SKF_NET_OFF  (-0x100000)
#define SKF_LL_OFF   (-0x200000)

#define BPF_NET_OFF  SKF_NET_OFF
#define BPF_LL_OFF   SKF_LL_OFF

#endif
