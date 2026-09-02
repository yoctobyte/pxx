/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_NET_ETHERNET_H
#define PXX_CRTL_NET_ETHERNET_H 1

/* <net/ethernet.h> -- the BSD-derived ethernet names, as glibc exposes them.

   IT EXISTS BECAUSE PROGRAMS PROBE FOR IT. busybox's networking/ifconfig.c
   includes it under HAVE_NET_ETHERNET_H and uses nothing from it; the
   configure-time answer is the whole contract. Reaching the HOST's copy
   instead is not a harmless fallback: glibc's spells its declarations inside
   __BEGIN_DECLS from <sys/cdefs.h>, which crtl does not define, so the
   preprocessor handed the parser a bare identifier at top level and the TU
   died on `stray token'. A header that exists is the fix; a __BEGIN_DECLS
   shim would only move the next mismatch further in.

   ETH_* would come from <linux/if_ether.h> on Linux, a KERNEL UAPI header
   that is the kernel's to ship and not crtl's to shadow. The four constants
   glibc's copy actually consumes are defined here instead, guarded, so that
   including the real linux/if_ether.h alongside this file stays legal and the
   values agree. They are frozen by the wire format, not by any libc. */

#include <stdint.h>

#ifndef ETH_ALEN
#define ETH_ALEN      6       /* octets in one ethernet address */
#endif
#ifndef ETH_HLEN
#define ETH_HLEN      14      /* total octets in header */
#endif
#ifndef ETH_ZLEN
#define ETH_ZLEN      60      /* min octets in frame, sans FCS */
#endif
#ifndef ETH_DATA_LEN
#define ETH_DATA_LEN  1500    /* max octets in payload */
#endif
#ifndef ETH_FRAME_LEN
#define ETH_FRAME_LEN 1514    /* max octets in frame, sans FCS */
#endif

/* PACKED, and it matters: without it the trailing uint16_t in ether_header
   sits at offset 14 either way here, but a compiler free to align the struct
   would pad its SIZE to 16 and a caller writing sizeof() bytes onto the wire
   would emit two extra octets. glibc marks both; so do we. */
struct ether_addr {
  uint8_t ether_addr_octet[ETH_ALEN];
} __attribute__ ((__packed__));

struct ether_header {
  uint8_t  ether_dhost[ETH_ALEN];   /* destination eth addr */
  uint8_t  ether_shost[ETH_ALEN];   /* source ether addr    */
  uint16_t ether_type;              /* packet type ID field */
} __attribute__ ((__packed__));

/* Ethernet protocol IDs -- IEEE-assigned, in host order. */
#define ETHERTYPE_PUP       0x0200  /* Xerox PUP */
#define ETHERTYPE_SPRITE    0x0500  /* Sprite */
#define ETHERTYPE_IP        0x0800  /* IP */
#define ETHERTYPE_ARP       0x0806  /* address resolution */
#define ETHERTYPE_REVARP    0x8035  /* reverse ARP */
#define ETHERTYPE_AT        0x809B  /* AppleTalk protocol */
#define ETHERTYPE_AARP      0x80F3  /* AppleTalk ARP */
#define ETHERTYPE_VLAN      0x8100  /* IEEE 802.1Q VLAN tagging */
#define ETHERTYPE_IPX       0x8137  /* IPX */
#define ETHERTYPE_IPV6      0x86dd  /* IP protocol version 6 */
#define ETHERTYPE_LOOPBACK  0x9000  /* used to test interfaces */

#define ETHER_ADDR_LEN  ETH_ALEN
#define ETHER_TYPE_LEN  2
#define ETHER_CRC_LEN   4
#define ETHER_HDR_LEN   ETH_HLEN
#define ETHER_MIN_LEN   (ETH_ZLEN + ETHER_CRC_LEN)
#define ETHER_MAX_LEN   (ETH_FRAME_LEN + ETHER_CRC_LEN)

#define ETHER_IS_VALID_LEN(foo) \
        ((foo) >= ETHER_MIN_LEN && (foo) <= ETHER_MAX_LEN)

/* The trailer-packet types start here; (type - ETHERTYPE_TRAIL) * 512 bytes of
   data precede the real header. Historical, and kept because the names are. */
#define ETHERTYPE_TRAIL     0x1000
#define ETHERTYPE_NTRAILER  16

#define ETHERMTU        ETH_DATA_LEN
#define ETHERMIN        (ETHER_MIN_LEN - ETHER_HDR_LEN - ETHER_CRC_LEN)

#endif
