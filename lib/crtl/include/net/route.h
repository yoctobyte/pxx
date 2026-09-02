/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <net/route.h> -- struct rtentry and the RTF_ flags.
 *
 * ANOTHER IOCTL ABI. SIOCADDRT/SIOCDELRT take a pointer to `struct rtentry'
 * and the kernel reads it field by field, so a member at the wrong offset adds
 * a route to somewhere else -- and succeeds. The layout is uapi/linux/route.h's,
 * including the two padding members that exist only to keep the following
 * fields where they are.
 *
 * rt_dst/rt_gateway/rt_genmask are `struct sockaddr', 16 bytes each, NOT
 * sockaddr_in: the field is the generic one and callers cast. That is what
 * makes the offsets independent of address family.
 *
 * struct in6_rtmsg is here too, as it is in glibc, because busybox's route.c
 * needs both in one file.
 *
 * Found attempting busybox rung 2: networking/route.c.
 */
#ifndef _CRTL_NET_ROUTE_H
#define _CRTL_NET_ROUTE_H

#include <sys/socket.h>
#include <netinet/in.h>

struct rtentry {
  unsigned long int rt_pad1;
  struct sockaddr rt_dst;         /* target address */
  struct sockaddr rt_gateway;     /* gateway, or 0 for a direct route */
  struct sockaddr rt_genmask;     /* target network mask */
  unsigned short int rt_flags;
  short int rt_pad2;
  unsigned long int rt_pad3;
  unsigned char rt_tos;
  unsigned char rt_class;
  short int rt_pad4[3];
  short int rt_metric;            /* +1, as the kernel wants it */
  char *rt_dev;                   /* forcing the device */
  unsigned long int rt_mtu;       /* per-route MTU/window */
  unsigned long int rt_window;    /* window clamping */
  unsigned short int rt_irtt;     /* initial RTT */
};

/* The kernel's own alias -- rt_mtu was called rt_mss before Linux 2.2 and
   busybox still writes that name. */
#define rt_mss rt_mtu

struct in6_rtmsg {
  struct in6_addr rtmsg_dst;
  struct in6_addr rtmsg_src;
  struct in6_addr rtmsg_gateway;
  uint32_t rtmsg_type;
  uint16_t rtmsg_dst_len;
  uint16_t rtmsg_src_len;
  uint32_t rtmsg_metric;
  unsigned long int rtmsg_info;
  uint32_t rtmsg_flags;
  int rtmsg_ifindex;
};

#define RTF_UP         0x0001   /* route usable */
#define RTF_GATEWAY    0x0002   /* destination is a gateway */
#define RTF_HOST       0x0004   /* host entry (net otherwise) */
#define RTF_REINSTATE  0x0008   /* reinstate after timeout */
#define RTF_DYNAMIC    0x0010   /* created dynamically (by redirect) */
#define RTF_MODIFIED   0x0020   /* modified dynamically (by redirect) */
#define RTF_MTU        0x0040   /* specific MTU for this route */
#define RTF_MSS        RTF_MTU  /* the pre-2.2 name */
#define RTF_WINDOW     0x0080   /* per route window clamping */
#define RTF_IRTT       0x0100   /* initial round trip time */
#define RTF_REJECT     0x0200   /* reject route */
#define RTF_STATIC     0x0400
#define RTF_XRESOLVE   0x0800
#define RTF_NOFORWARD  0x1000
#define RTF_THROW      0x2000
#define RTF_NOPMTUDISC 0x4000

/* IPv6-only flags (uapi/linux/ipv6_route.h) -- route.c prints them from the
   same table as the ones above. */
#define RTF_DEFAULT    0x00010000
#define RTF_ALLONLINK  0x00020000
#define RTF_ADDRCONF   0x00040000
#define RTF_LINKRT     0x00100000
#define RTF_NONEXTHOP  0x00200000
#define RTF_CACHE      0x01000000
#define RTF_FLOW       0x02000000
#define RTF_POLICY     0x04000000
#define RTF_LOCAL      0x80000000

#define RTF_ADDRCLASSMASK 0xF8000000
#define RT_ADDRCLASS(flags) ((uint32_t)(flags) >> 23)
#define RT_TOS(tos) ((tos) & IPTOS_TOS_MASK)
#define RT_LOCALADDR(flags) \
  (((flags) & RTF_ADDRCLASSMASK) == (RTF_LOCAL | RTF_INTERFACE))
#define RTF_INTERFACE  0x40000000
#define RTF_MULTICAST  0x20000000
#define RTF_BROADCAST  0x10000000
#define RTF_NAT        0x08000000

#endif
