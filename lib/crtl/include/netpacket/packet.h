/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <netpacket/packet.h> -- AF_PACKET's address, struct sockaddr_ll.
 *
 * THE ADDRESS IS THE HEADER'S WHOLE JOB. The PACKET_* socket options and the
 * SOL_PACKET level already live in <sys/socket.h> here (they were added
 * attempting busybox's udhcp), so this file adds the one thing that is
 * genuinely AF_PACKET's: the sockaddr a raw ethernet socket binds and receives
 * on. The PACKET_HOST..PACKET_OUTGOING values below are the sll_pkttype
 * ENUMERATION and not socket options -- same prefix, different namespace, and
 * the kernel spells both in linux/if_packet.h -- so they are #ifndef-guarded
 * to stay compatible with a program that also includes the UAPI header.
 *
 * sll_addr IS EIGHT BYTES, NOT SIX. It is sized for the longest hardware
 * address the kernel supports rather than for ethernet, and sll_halen says how
 * much of it is real; a six-byte version has the right layout for every field
 * before it and the wrong sizeof, which is what a `bind(fd, &sa, sizeof sa)'
 * passes to the kernel.
 *
 * Found attempting busybox on i386: 3 translation units (udhcp/packet.c,
 * udhcp/socket.c, udhcp/arpping.c).
 * feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_NETPACKET_PACKET_H
#define _CRTL_NETPACKET_PACKET_H

#include <stdint.h>
#include <sys/socket.h>

struct sockaddr_ll {
  unsigned short sll_family;    /* always AF_PACKET */
  uint16_t       sll_protocol;  /* ETH_P_* , in NETWORK order */
  int            sll_ifindex;   /* interface index; 0 is "any" */
  unsigned short sll_hatype;    /* ARPHRD_* */
  unsigned char  sll_pkttype;   /* PACKET_HOST etc, below */
  unsigned char  sll_halen;     /* how much of sll_addr is real */
  unsigned char  sll_addr[8];   /* the kernel's maximum, not ethernet's six */
};

/* sll_pkttype values -- an enumeration, NOT socket options. */
#ifndef PACKET_HOST
#define PACKET_HOST      0   /* addressed to us */
#endif
#ifndef PACKET_BROADCAST
#define PACKET_BROADCAST 1
#endif
#ifndef PACKET_MULTICAST
#define PACKET_MULTICAST 2
#endif
#ifndef PACKET_OTHERHOST
#define PACKET_OTHERHOST 3   /* addressed to someone else */
#endif
#ifndef PACKET_OUTGOING
#define PACKET_OUTGOING  4   /* sent by us, looped back */
#endif

#endif
