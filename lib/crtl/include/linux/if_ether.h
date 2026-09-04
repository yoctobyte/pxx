/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_LINUX_IF_ETHER_H
#define PXX_CRTL_LINUX_IF_ETHER_H 1

/* <linux/if_ether.h> -- the ETH_P_* protocol identifiers and the frame
   geometry, as the kernel's user-facing header exposes them.

   WHY THIS EXISTS, WHEN <net/ethernet.h> SAYS THE OPPOSITE. That file's
   comment reasons that ETH_* "would come from <linux/if_ether.h>, a KERNEL
   UAPI header that is the kernel's to ship and not crtl's to shadow", and
   defines only the four constants glibc's own copy consumes. The reasoning was
   sound for a native build and is wrong for this compiler, because CROSS
   TARGETS HAVE NO HOST HEADER TO FALL BACK TO: the fallback into /usr/include
   is native-only by design, so on i386 or arm32 there is no linux/if_ether.h
   anywhere and ETH_P_IP is simply absent.

   AND AN ABSENT CONSTANT HERE DOES NOT REFUSE -- IT BECOMES ZERO. pxx accepts
   an undeclared identifier used as a value and warns
   (bug-c-an-undeclared-identifier-used-as-a-value-is-a-warning-not-an-error),
   so every one of these went in as 0 with the build still green. Measured
   2026-09-04 over the 258-applet busybox build on x86-64: ETH_P_IP zero in
   networking/udhcp/{arpping,dhcpc,packet}.c and networking/arping.c, ETH_P_ARP
   zero in arpping.c and arping.c. A raw socket asking for protocol 0 is not a
   compile error and not a run-time error either -- it binds to nothing and the
   applet waits forever. That is the class this header closes.

   THESE ARE WIRE VALUES. They travel to the kernel and onto the network, so a
   wrong one does not fail to compile, it asks for a different thing --
   the same hazard <linux/if_vlan.h> records. Every value here is asserted
   against gcc's view of the real header by test/c_crtl_header_constants.c, which
   fails on a one-digit change.

   NOT AN ARCH-DEPENDENT HEADER: the kernel defines these once in
   include/uapi/linux/if_ether.h with no per-arch override, so there is one
   arm to keep correct rather than five. */

#include <stdint.h>

/* Frame geometry. Also defined, guarded, in <net/ethernet.h> -- including both
   headers in one TU is legal and they agree. */
#ifndef ETH_ALEN
#define ETH_ALEN      6       /* octets in one ethernet address */
#endif
#ifndef ETH_TLEN
#define ETH_TLEN      2       /* octets in the type field */
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
#ifndef ETH_FCS_LEN
#define ETH_FCS_LEN   4       /* octets in the FCS */
#endif
#ifndef ETH_MIN_MTU
#define ETH_MIN_MTU   68      /* min IPv4 MTU per RFC791 */
#endif
#ifndef ETH_MAX_MTU
#define ETH_MAX_MTU   0xFFFFU /* 65535, same as IP_MAX_MTU */
#endif

/* Protocol identifiers, as they appear in the ethernet type field and in
   socket(AF_PACKET, ..., htons(ETH_P_x)). Network byte order on the wire; the
   constants are in host order and callers pass them through htons(). */
#define ETH_P_LOOP      0x0060  /* ethernet loopback packet */
#define ETH_P_PUP       0x0200  /* Xerox PUP packet */
#define ETH_P_PUPAT     0x0201  /* Xerox PUP addr trans packet */
#define ETH_P_IP        0x0800  /* internet protocol packet */
#define ETH_P_X25       0x0805  /* CCITT X.25 */
#define ETH_P_ARP       0x0806  /* address resolution packet */
#define ETH_P_BPQ       0x08FF  /* G8BPQ AX.25 ethernet packet */
#define ETH_P_IEEEPUP   0x0a00  /* Xerox IEEE802.3 PUP packet */
#define ETH_P_IEEEPUPAT 0x0a01  /* Xerox IEEE802.3 PUP addr trans packet */
#define ETH_P_DEC       0x6000  /* DEC assigned proto */
#define ETH_P_RARP      0x8035  /* reverse addr resolution packet */
#define ETH_P_ATALK     0x809B  /* Appletalk DDP */
#define ETH_P_AARP      0x80F3  /* Appletalk AARP */
#define ETH_P_8021Q     0x8100  /* 802.1Q VLAN Extended Header */
#define ETH_P_IPX       0x8137  /* IPX over DIX */
#define ETH_P_IPV6      0x86DD  /* IPv6 over bluebook */
#define ETH_P_PAUSE     0x8808  /* IEEE Pause frames */
#define ETH_P_SLOW      0x8809  /* Slow Protocol (802.3ad) */
#define ETH_P_WCCP      0x883E  /* Web-cache coordination protocol */
#define ETH_P_PPP_DISC  0x8863  /* PPPoE discovery messages */
#define ETH_P_PPP_SES   0x8864  /* PPPoE session messages */
#define ETH_P_MPLS_UC   0x8847  /* MPLS Unicast traffic */
#define ETH_P_MPLS_MC   0x8848  /* MPLS Multicast traffic */
#define ETH_P_ATMFATE   0x8884  /* Frame-based ATM Transport over Ethernet */
#define ETH_P_AOE       0x88A2  /* ATA over Ethernet */
#define ETH_P_8021AD    0x88A8  /* 802.1ad Service VLAN */
#define ETH_P_TIPC      0x88CA  /* TIPC */
#define ETH_P_LLDP      0x88CC  /* Link Layer Discovery Protocol */
#define ETH_P_FCOE      0x8906  /* Fibre Channel over Ethernet */
#define ETH_P_FIP       0x8914  /* FCoE Initialization Protocol */
#define ETH_P_EDSA      0xDADA  /* Ethertype DSA */

/* Non-DIX types: values below 1536 cannot appear in a real type field, so the
   kernel uses that space for its own pseudo-protocols. ETH_P_ALL is the one
   busybox reaches for, in a packet socket that wants every frame. */
#define ETH_P_802_3     0x0001  /* dummy type for 802.3 frames */
#define ETH_P_AX25      0x0002  /* dummy protocol id for AX.25 */
#define ETH_P_ALL       0x0003  /* every packet (be careful) */
#define ETH_P_802_2     0x0004  /* 802.2 frames */
#define ETH_P_SNAP      0x0005  /* internal only */
#define ETH_P_DDCMP     0x0006  /* DEC DDCMP: internal only */
#define ETH_P_WAN_PPP   0x0007  /* Dummy type for WAN PPP frames */
#define ETH_P_PPP_MP    0x0008  /* Dummy type for PPP MP frames */
#define ETH_P_LOCALTALK 0x0009  /* Localtalk pseudo type */
#define ETH_P_CAN       0x000C  /* CAN: Controller Area Network */
#define ETH_P_CANFD     0x000D  /* CANFD: CAN flexible data rate */
#define ETH_P_PPPTALK   0x0010  /* Dummy type for Atalk over PPP */
#define ETH_P_TR_802_2  0x0011  /* 802.2 frames */
#define ETH_P_MOBITEX   0x0015  /* Mobitex (kaz@cafe.net) */
#define ETH_P_CONTROL   0x0016  /* Card specific control frames */
#define ETH_P_IRDA      0x0017  /* Linux-IrDA */
#define ETH_P_ECONET    0x0018  /* Acorn Econet */
#define ETH_P_HDLC      0x0019  /* HDLC frames */
#define ETH_P_ARCNET    0x001A  /* 1A for ArcNet :-) */
#define ETH_P_DSA       0x001B  /* Distributed Switch Arch. */
#define ETH_P_TRAILER   0x001C  /* Trailer switch tagging */
#define ETH_P_PHONET    0x00F5  /* Nokia Phonet frames */
#define ETH_P_IEEE802154 0x00F6 /* IEEE802.15.4 frame */
#define ETH_P_CAIF      0x00F7  /* ST-Ericsson CAIF protocol */
#define ETH_P_XDSA      0x00F8  /* Multiplexed DSA protocol */

/* WHERE THE LIST STOPS, AND WHAT AN ABSENT ONE COSTS. The kernel's copy
   carries 47 more identifiers than this file -- MACsec, PROFINET, EtherCAT,
   the QinQ and DSA experiments. None is reachable from anything in this tree,
   and each one added is a value transcribed, so the list stops at the wire-
   common set plus everything busybox names. An absent one is NOT a compile
   error today: it becomes 0 with a warning, which is the very defect this
   header was written to close, so anyone extending crtl into one of those
   protocols must add the constant rather than assume the compiler will say so.
   The general repair for that is
   bug-c-an-undeclared-identifier-used-as-a-value-is-a-warning-not-an-error,
   in Track C; this header removes the busybox-sized instance of it. To extend:
   copy the value from the kernel's include/uapi/linux/if_ether.h and add a row
   to test/c_crtl_header_constants.c, which is what makes it a checked value
   rather than a typed one. */

/* The frame header, as it sits on the wire. */
struct ethhdr {
  unsigned char h_dest[ETH_ALEN];   /* destination eth addr */
  unsigned char h_source[ETH_ALEN]; /* source ether addr    */
  uint16_t      h_proto;            /* packet type ID field, network order */
};

#endif /* PXX_CRTL_LINUX_IF_ETHER_H */
