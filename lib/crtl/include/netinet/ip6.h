/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <netinet/ip6.h>, the IPv6 header (RFC 8200) in the BSD/RFC 3542
 * spelling. Version, traffic class and flow label share the first 32-bit
 * word (ip6_flow); ip6_vfc is its first byte. Every multi-byte field is in
 * network order, as on the wire. Added for dhcpcd (ipv6nd.c, dhcp6.c).
 */
#ifndef _CRTL_NETINET_IP6_H
#define _CRTL_NETINET_IP6_H
#include <stdint.h>
#include <netinet/in.h>

struct ip6_hdrctl {
  uint32_t ip6_un1_flow;   /* 4 bits version, 8 traffic class, 20 flow label */
  uint16_t ip6_un1_plen;   /* payload length */
  uint8_t  ip6_un1_nxt;    /* next header */
  uint8_t  ip6_un1_hlim;   /* hop limit */
};

struct ip6_hdr {
  union {
    struct ip6_hdrctl ip6_un1;
    uint8_t ip6_un2_vfc;   /* 4 bits version, top 4 bits of the class */
  } ip6_ctlun;
  struct in6_addr ip6_src;
  struct in6_addr ip6_dst;
};
#define ip6_vfc  ip6_ctlun.ip6_un2_vfc
#define ip6_flow ip6_ctlun.ip6_un1.ip6_un1_flow
#define ip6_plen ip6_ctlun.ip6_un1.ip6_un1_plen
#define ip6_nxt  ip6_ctlun.ip6_un1.ip6_un1_nxt
#define ip6_hlim ip6_ctlun.ip6_un1.ip6_un1_hlim
#define ip6_hops ip6_ctlun.ip6_un1.ip6_un1_hlim

/* a generic extension header's first two bytes */
struct ip6_ext {
  uint8_t ip6e_nxt;
  uint8_t ip6e_len;
};

#endif
