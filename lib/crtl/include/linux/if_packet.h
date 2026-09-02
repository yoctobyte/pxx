/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <linux/if_packet.h> -- AF_PACKET's socket options.
 *
 * struct sockaddr_ll IS NOT DEFINED HERE. It comes from <netpacket/packet.h>,
 * which this header includes, and that is a DELIBERATE divergence from both
 * glibc and the kernel: upstream each of the two headers declares its own copy,
 * so including both is a redefinition error and portable code has to pick one
 * and stay with it. One definition site removes the choice. A program that
 * includes both here gets sockaddr_ll once, which is strictly more than glibc
 * accepts and never less.
 *
 * PACKET_HOST..PACKET_OUTGOING ARE sll_pkttype VALUES; PACKET_ADD_MEMBERSHIP
 * ONWARD ARE setsockopt OPTION NAMES. They are two vocabularies numbered from
 * the same small integers -- PACKET_MULTICAST is 2 and so is
 * PACKET_DROP_MEMBERSHIP, PACKET_OUTGOING is 4 and PACKET_RX_RING is 5 -- so a
 * value taken from the wrong one is always a legal value of the other. The
 * pkttype half is in <netpacket/packet.h> beside the field it fills; the
 * option half is here beside setsockopt, which is what keeps them apart.
 *
 * PACKET_FASTROUTE AND PACKET_USER ARE BOTH 6, in the kernel's own header, one
 * of them dead. Transcribed as it stands rather than tidied.
 *
 * THE MMAP RING IS NOT HERE. tpacket_req, tpacket_hdr and the TPACKET_V*
 * layouts are a large interface that nothing has asked crtl for; a constant no
 * call site passes is a promise this runtime has not been asked to keep. What
 * IS here is what a plain AF_PACKET socket uses: the options, the fanout
 * selectors, and struct tpacket_auxdata, which arrives as a cmsg on an
 * ordinary recvmsg once PACKET_AUXDATA is set.
 *
 * Found attempting busybox on i386: networking/udhcp/dhcpc.c, which sets
 * PACKET_AUXDATA to see the VLAN tag the kernel stripped.
 * feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_LINUX_IF_PACKET_H
#define _CRTL_LINUX_IF_PACKET_H

#include <linux/types.h>
#include <netpacket/packet.h>   /* struct sockaddr_ll and the PACKET_* pkttypes */

struct sockaddr_pkt {
  unsigned short spkt_family;
  unsigned char  spkt_device[14];
  __be16         spkt_protocol;
};

/* setsockopt/getsockopt names at SOL_PACKET. See the note above: these share
   their numbers with the sll_pkttype values. */
#define PACKET_ADD_MEMBERSHIP   1
#define PACKET_DROP_MEMBERSHIP  2
#define PACKET_RECV_OUTPUT      3
/* Value 4 is unused. */
#define PACKET_RX_RING          5
#define PACKET_STATISTICS       6
#define PACKET_COPY_THRESH      7
#define PACKET_AUXDATA          8
#define PACKET_ORIGDEV          9
#define PACKET_VERSION          10
#define PACKET_HDRLEN           11
#define PACKET_RESERVE          12
#define PACKET_TX_RING          13
#define PACKET_LOSS             14
#define PACKET_VNET_HDR         15
#define PACKET_TX_TIMESTAMP     16
#define PACKET_TIMESTAMP        17
#define PACKET_FANOUT           18
#define PACKET_TX_HAS_OFF       19
#define PACKET_QDISC_BYPASS     20
#define PACKET_ROLLOVER_STATS   21
#define PACKET_FANOUT_DATA      22
#define PACKET_IGNORE_OUTGOING  23
#define PACKET_VNET_HDR_SZ      24

#define PACKET_FANOUT_HASH       0
#define PACKET_FANOUT_LB         1
#define PACKET_FANOUT_CPU        2
#define PACKET_FANOUT_ROLLOVER   3
#define PACKET_FANOUT_RND        4
#define PACKET_FANOUT_QM         5
#define PACKET_FANOUT_CBPF       6
#define PACKET_FANOUT_EBPF       7
#define PACKET_FANOUT_FLAG_ROLLOVER         0x1000
#define PACKET_FANOUT_FLAG_UNIQUEID         0x2000
#define PACKET_FANOUT_FLAG_IGNORE_OUTGOING  0x4000
#define PACKET_FANOUT_FLAG_DEFRAG           0x8000

struct tpacket_stats {
  unsigned int tp_packets;
  unsigned int tp_drops;
};

struct tpacket_stats_v3 {
  unsigned int tp_packets;
  unsigned int tp_drops;
  unsigned int tp_freeze_q_cnt;
};

union tpacket_stats_u {
  struct tpacket_stats stats1;
  struct tpacket_stats_v3 stats3;
};

/* Arrives as a SOL_PACKET cmsg on an ordinary recvmsg once PACKET_AUXDATA is
   set -- no ring buffer involved. */
struct tpacket_auxdata {
  __u32 tp_status;
  __u32 tp_len;
  __u32 tp_snaplen;
  __u16 tp_mac;
  __u16 tp_net;
  __u16 tp_vlan_tci;
  __u16 tp_vlan_tpid;
};

#define TP_STATUS_KERNEL           0
#define TP_STATUS_USER             (1 << 0)
#define TP_STATUS_COPY             (1 << 1)
#define TP_STATUS_LOSING           (1 << 2)
#define TP_STATUS_CSUMNOTREADY     (1 << 3)
#define TP_STATUS_VLAN_VALID       (1 << 4)  /* auxdata has valid tp_vlan_tci */
#define TP_STATUS_BLK_TMO          (1 << 5)
#define TP_STATUS_VLAN_TPID_VALID  (1 << 6)  /* auxdata has valid tp_vlan_tpid */
#define TP_STATUS_CSUM_VALID       (1 << 7)
#define TP_STATUS_GSO_TCP          (1 << 8)

#endif
