/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <netinet/udp.h> -- the UDP header.
 *
 * BOTH SPELLINGS, like <netinet/ip.h> beside it and for the same reason: they
 * are the SAME EIGHT BYTES under two names. `source/dest/len/check' is Linux's
 * `struct udphdr' and `uh_sport/uh_dport/uh_ulen/uh_sum' is BSD's, and glibc
 * ships both from this one header. busybox uses BOTH, in the same build:
 * networking/udhcp/packet.c writes `packet.udp.source' and
 * networking/traceroute.c reads `up->uh_dport'. A header carrying only one
 * spelling compiles half the corpus and looks finished.
 *
 * The union is how glibc does it (a `#ifdef __FAVOR_BSD' pair there, chosen at
 * compile time); a union gives both at once and costs nothing, because the two
 * layouts are identical field for field.
 *
 * Found attempting busybox on i386, where there is no host <netinet/udp.h> to
 * fall back on: 7 translation units stop here
 * (feature-c-corpus-busybox-i386-the-second-architecture).
 */
#ifndef _CRTL_NETINET_UDP_H
#define _CRTL_NETINET_UDP_H

#include <stdint.h>

struct udphdr {
  union {
    struct {
      uint16_t uh_sport;
      uint16_t uh_dport;
      uint16_t uh_ulen;
      uint16_t uh_sum;
    };
    struct {
      uint16_t source;
      uint16_t dest;
      uint16_t len;
      uint16_t check;
    };
  };
};

#endif
