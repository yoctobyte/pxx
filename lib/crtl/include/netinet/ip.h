/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <netinet/ip.h> -- the IPv4 header.
 *
 * BOTH SPELLINGS, because both are in use and they are the SAME BYTES: `struct
 * iphdr' is Linux's and `struct ip' is BSD's, and glibc ships both from this
 * header. A program that reads a raw socket gets whichever it declared.
 *
 * THE FIRST BYTE IS TWO NIBBLES AND THEIR ORDER IS ENDIAN-DEPENDENT. On a
 * little-endian machine `ihl' is declared first and lands in the LOW nibble;
 * on big-endian `version' comes first. Every target this runtime builds for is
 * little-endian, so only that arm exists here -- and it is written as a
 * conditional anyway, so that adding a big-endian target is a compile error
 * naming this spot rather than a silently swapped nibble.
 *
 * Found attempting busybox rung 2: networking/ping.c reads iphdr.ihl off the
 * received packet to find where the ICMP header starts.
 */
#ifndef _CRTL_NETINET_IP_H
#define _CRTL_NETINET_IP_H

#include <stdint.h>
#include <netinet/in.h>

struct iphdr {
#if defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
  unsigned int version:4;
  unsigned int ihl:4;
#else
  unsigned int ihl:4;
  unsigned int version:4;
#endif
  uint8_t  tos;
  uint16_t tot_len;
  uint16_t id;
  uint16_t frag_off;
  uint8_t  ttl;
  uint8_t  protocol;
  uint16_t check;
  uint32_t saddr;
  uint32_t daddr;
  /* Options follow when ihl > 5. */
};

/* The BSD names for the same header. */
struct ip {
#if defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
  unsigned int ip_v:4;
  unsigned int ip_hl:4;
#else
  unsigned int ip_hl:4;
  unsigned int ip_v:4;
#endif
  uint8_t  ip_tos;
  uint16_t ip_len;
  uint16_t ip_id;
  uint16_t ip_off;
  uint8_t  ip_ttl;
  uint8_t  ip_p;
  uint16_t ip_sum;
  struct in_addr ip_src;
  struct in_addr ip_dst;
};

#define IP_RF      0x8000   /* reserved fragment flag */
#define IP_DF      0x4000   /* don't fragment */
#define IP_MF      0x2000   /* more fragments */
#define IP_OFFMASK 0x1fff   /* fragment offset, in 8-byte units */

/* Type-of-service / DSCP. */
#define IPTOS_TOS_MASK    0x1E
#define IPTOS_TOS(tos)    ((tos) & IPTOS_TOS_MASK)
#define IPTOS_LOWDELAY    0x10
#define IPTOS_THROUGHPUT  0x08
#define IPTOS_RELIABILITY 0x04
#define IPTOS_LOWCOST     0x02
#define IPTOS_MINCOST     IPTOS_LOWCOST

#define IPTOS_PREC_MASK            0xE0
#define IPTOS_PREC(tos)            ((tos) & IPTOS_PREC_MASK)
#define IPTOS_PREC_NETCONTROL      0xE0
#define IPTOS_PREC_INTERNETCONTROL 0xC0
#define IPTOS_PREC_CRITIC_ECP      0xA0
#define IPTOS_PREC_FLASHOVERRIDE   0x80
#define IPTOS_PREC_FLASH           0x60
#define IPTOS_PREC_IMMEDIATE       0x40
#define IPTOS_PREC_PRIORITY        0x20
#define IPTOS_PREC_ROUTINE         0x00

#define IPVERSION 4
#define IP_MAXPACKET 65535

#endif
