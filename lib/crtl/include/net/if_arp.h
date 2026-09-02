/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <net/if_arp.h> -- struct arpreq, the hardware types, the flags.
 *
 * SIOCSARP/SIOCDARP/SIOCGARP read `struct arpreq' the same way the route
 * ioctls read struct rtentry: by offset, without checking. arp_pa, arp_ha and
 * arp_netmask are generic `struct sockaddr' -- and arp_ha carries a HARDWARE
 * address in a structure whose sa_family field names the ARPHRD_ type rather
 * than an AF_, which is the one genuinely confusing thing in this header and
 * is the kernel's design, not a shortcut here.
 *
 * struct arphdr is the on-the-wire ARP header; the addresses that follow it
 * are variable-length and therefore NOT members, which is why the struct looks
 * too short.
 *
 * Found attempting busybox rung 2: networking/arp.c, ifconfig.c.
 */
#ifndef _CRTL_NET_IF_ARP_H
#define _CRTL_NET_IF_ARP_H

#include <stdint.h>
#include <sys/socket.h>
#include <net/if.h>

/* ARP protocol opcodes. */
#define ARPOP_REQUEST   1
#define ARPOP_REPLY     2
#define ARPOP_RREQUEST  3
#define ARPOP_RREPLY    4
#define ARPOP_InREQUEST 8
#define ARPOP_InREPLY   9
#define ARPOP_NAK      10

/* Hardware types. These are what travels in arp_ha.sa_family. */
#define ARPHRD_NETROM     0
#define ARPHRD_ETHER      1
#define ARPHRD_EETHER     2
#define ARPHRD_AX25       3
#define ARPHRD_PRONET     4
#define ARPHRD_CHAOS      5
#define ARPHRD_IEEE802    6
#define ARPHRD_ARCNET     7
#define ARPHRD_APPLETLK   8
#define ARPHRD_DLCI      15
#define ARPHRD_ATM       19
#define ARPHRD_METRICOM  23
#define ARPHRD_IEEE1394  24
#define ARPHRD_EUI64     27
#define ARPHRD_INFINIBAND 32
#define ARPHRD_SLIP     256
#define ARPHRD_CSLIP    257
#define ARPHRD_SLIP6    258
#define ARPHRD_CSLIP6   259
#define ARPHRD_RSRVD    260
#define ARPHRD_ADAPT    264
#define ARPHRD_ROSE     270
#define ARPHRD_X25      271
#define ARPHRD_HWX25    272
#define ARPHRD_PPP      512
#define ARPHRD_CISCO    513
#define ARPHRD_HDLC     ARPHRD_CISCO
#define ARPHRD_LAPB     516
#define ARPHRD_DDCMP    517
#define ARPHRD_RAWHDLC  518
#define ARPHRD_TUNNEL   768
#define ARPHRD_TUNNEL6  769
#define ARPHRD_FRAD     770
#define ARPHRD_SKIP     771
#define ARPHRD_LOOPBACK 772
#define ARPHRD_LOCALTLK 773
#define ARPHRD_FDDI     774
#define ARPHRD_BIF      775
#define ARPHRD_SIT      776
#define ARPHRD_IPDDP    777
#define ARPHRD_IPGRE    778
#define ARPHRD_PIMREG   779
#define ARPHRD_HIPPI    780
#define ARPHRD_ASH      781
#define ARPHRD_ECONET   782
#define ARPHRD_IRDA     783
#define ARPHRD_FCPP     784
#define ARPHRD_FCAL     785
#define ARPHRD_FCPL     786
#define ARPHRD_FCFABRIC 787
#define ARPHRD_IEEE802_TR 800
#define ARPHRD_IEEE80211  801
#define ARPHRD_IEEE80211_PRISM 802
#define ARPHRD_IEEE80211_RADIOTAP 803
#define ARPHRD_IEEE802154 804
#define ARPHRD_VOID     0xFFFF
#define ARPHRD_NONE     0xFFFE

/* arp_flags. ATF_COM means the entry is complete -- has a hardware address. */
#define ATF_COM      0x02
#define ATF_PERM     0x04
#define ATF_PUBL     0x08
#define ATF_USETRAILERS 0x10
#define ATF_NETMASK  0x20
#define ATF_DONTPUB  0x40
#define ATF_MAGIC    0x80

struct arpreq {
  struct sockaddr arp_pa;        /* protocol address */
  struct sockaddr arp_ha;        /* hardware address; sa_family is an ARPHRD_ */
  int arp_flags;
  struct sockaddr arp_netmask;   /* only for proxy ARP entries */
  char arp_dev[16];
};

struct arpreq_old {
  struct sockaddr arp_pa;
  struct sockaddr arp_ha;
  int arp_flags;
  struct sockaddr arp_netmask;
};

/* The on-the-wire header. The sender/target addresses follow it and are
   variable-length, so they are deliberately not members. */
struct arphdr {
  uint16_t ar_hrd;   /* format of hardware address */
  uint16_t ar_pro;   /* format of protocol address */
  uint8_t  ar_hln;   /* length of hardware address */
  uint8_t  ar_pln;   /* length of protocol address */
  uint16_t ar_op;    /* ARP opcode */
};

#endif
