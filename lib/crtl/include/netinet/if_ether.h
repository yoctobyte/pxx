/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <netinet/if_ether.h> -- the BSD ARP-over-ethernet names.
 *
 * MOSTLY A JOIN, and deliberately so: glibc's copy is <net/ethernet.h> and
 * <net/if_arp.h> together plus `struct ether_arp' and the ETHER_* aliases, and
 * both of those headers already exist here. Redefining struct ether_header or
 * the ARPOP_ values here instead would be a second copy of a wire format, and
 * the second copy is the one that drifts.
 *
 * `struct ether_arp' is PACKED for the reason struct ether_header is: it is
 * read off and written onto the wire by sizeof, and a compiler free to align
 * would make sizeof 30 instead of 28 and put two octets of padding on the
 * network.
 *
 * The ETHER_* lengths are the ETH_* ones under BSD names -- same numbers, and
 * they are frozen by the frame format rather than by any libc.
 *
 * Found attempting busybox on i386, where there is no host header to fall back
 * on: udhcp/packet.c, udhcp/dhcpc.c and udhcp/arpping.c include it (the first
 * two for nothing but the join; arpping.c also takes net/if_arp.h itself).
 * feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_NETINET_IF_ETHER_H
#define _CRTL_NETINET_IF_ETHER_H

#include <stdint.h>
#include <linux/if_ether.h>
#include <net/ethernet.h>
#include <net/if_arp.h>

/* <linux/if_ether.h> ADDED 2026-09-04, and it is the join that was missing.
   glibc's copy of this header includes it first, and without it the ETH_P_*
   protocol identifiers had no definition anywhere in crtl. That does not
   refuse -- pxx warns and substitutes 0 -- so networking/udhcp/arpping.c
   asked for `htons(0)' on its packet socket and networking/arping.c built ARP
   frames with a zero ethertype, in a build that was green over 621 cases. */

#define ETHER_ADDR_LEN  ETH_ALEN
#define ETHER_TYPE_LEN  2
#define ETHER_CRC_LEN   4
#define ETHER_HDR_LEN   ETH_HLEN
#define ETHER_MIN_LEN   (ETH_ZLEN + ETHER_CRC_LEN)
#define ETHER_MAX_LEN   (ETH_FRAME_LEN + ETHER_CRC_LEN)

#define ETHER_IS_VALID_LEN(foo) \
  ((foo) >= ETHER_MIN_LEN && (foo) <= ETHER_MAX_LEN)

/* ARP over ethernet over IPv4: the header, then the four addresses it
   describes, which glibc spells out here because at these two protocol types
   they are fixed-length. */
struct ether_arp {
  struct arphdr ea_hdr;                 /* fixed-size header */
  uint8_t arp_sha[ETH_ALEN];            /* sender hardware address */
  uint8_t arp_spa[4];                   /* sender protocol address */
  uint8_t arp_tha[ETH_ALEN];            /* target hardware address */
  uint8_t arp_tpa[4];                   /* target protocol address */
} __attribute__ ((__packed__));

#define arp_hrd ea_hdr.ar_hrd
#define arp_pro ea_hdr.ar_pro
#define arp_hln ea_hdr.ar_hln
#define arp_pln ea_hdr.ar_pln
#define arp_op  ea_hdr.ar_op

#endif
