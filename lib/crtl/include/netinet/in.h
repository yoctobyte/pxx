/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_NETINET_IN_H
#define PXX_CRTL_NETINET_IN_H 1

#include <stdint.h>
#include <sys/socket.h>

/* Byte-order helpers. Implemented in socket.c and also declared by
   <arpa/inet.h>; glibc's <netinet/in.h> declares them too, and network code
   routinely includes only this header and expects htons() to be there.
   Duplicate matching declarations across the two headers are fine in C. */
uint16_t htons(uint16_t hostshort);
uint16_t ntohs(uint16_t netshort);
uint32_t htonl(uint32_t hostlong);
uint32_t ntohl(uint32_t netlong);

typedef uint16_t in_port_t;
typedef uint32_t in_addr_t;

struct in_addr {
  in_addr_t s_addr;
};

struct sockaddr_in {
  sa_family_t sin_family;
  in_port_t sin_port;
  struct in_addr sin_addr;
  unsigned char sin_zero[8];
};

#define IPPROTO_IP 0
#define IPPROTO_TCP 6
#define IPPROTO_UDP 17

#define INADDR_ANY 0x00000000U
#define INADDR_LOOPBACK 0x7F000001U
#define INADDR_BROADCAST 0xFFFFFFFFU
#define INADDR_NONE 0xFFFFFFFFU

/* The classful address predicates. THESE TAKE A HOST-ORDER ADDRESS, which is
   why every caller wraps the argument in ntohl() -- busybox
   networking/libiproute/iptunnel.c:349, :353 and :357 all spell
   `IN_MULTICAST(ntohl(p->iph.daddr))'. Handing one a network-order address
   compiles, runs, and answers about the wrong byte.

   IN_MULTICAST is defined through IN_CLASSD rather than open-coded, because
   that is the relation that makes the constant checkable: class D is
   224.0.0.0/4, so the test is the top four bits being 1110. */
#define IN_CLASSA(a)       ((((uint32_t)(a)) & 0x80000000U) == 0)
#define IN_CLASSB(a)       ((((uint32_t)(a)) & 0xC0000000U) == 0x80000000U)
#define IN_CLASSC(a)       ((((uint32_t)(a)) & 0xE0000000U) == 0xC0000000U)
#define IN_CLASSD(a)       ((((uint32_t)(a)) & 0xF0000000U) == 0xE0000000U)
#define IN_MULTICAST(a)    IN_CLASSD(a)
#define IN_EXPERIMENTAL(a) ((((uint32_t)(a)) & 0xF0000000U) == 0xF0000000U)
#define IN_BADCLASS(a)     IN_EXPERIMENTAL(a)

#define IPPROTO_ICMP   1
#define IPPROTO_IGMP   2
#define IPPROTO_IPIP   4
#define IPPROTO_EGP    8
#define IPPROTO_PUP   12
#define IPPROTO_IDP   22
#define IPPROTO_TP    29
#define IPPROTO_IPV6  41
#define IPPROTO_ROUTING 43
#define IPPROTO_FRAGMENT 44
#define IPPROTO_RSVP  46
#define IPPROTO_GRE   47
#define IPPROTO_ESP   50
#define IPPROTO_AH    51
#define IPPROTO_ICMPV6 58
#define IPPROTO_NONE  59
#define IPPROTO_DSTOPTS 60
#define IPPROTO_SCTP 132
#define IPPROTO_UDPLITE 136
#define IPPROTO_RAW  255

/* IPPROTO_IP level socket options -- setsockopt(fd, IPPROTO_IP, IP_x, ...).
   NONE OF THESE EXISTED HERE BEFORE 2026-09-04, and an absent one does not
   refuse: pxx warns and substitutes 0, and 0 is not a valid option number, so
   the call reaches the kernel as a request for something else. Measured over
   the 258-applet busybox build: networking/traceroute.c:1077 sets
   IP_MULTICAST_IF and got 0. The values are the kernel's, generated from
   include/uapi/linux/in.h rather than transcribed, and asserted row by row in
   test/c_crtl_header_constants.c. They are uniform across every Linux
   architecture -- this is protocol numbering, not an ABI. */
#define IP_TOS                      1
#define IP_TTL                      2
#define IP_HDRINCL                  3
#define IP_OPTIONS                  4
#define IP_ROUTER_ALERT             5
#define IP_RECVOPTS                 6
#define IP_RETOPTS                  7
#define IP_PKTINFO                  8
#define IP_PKTOPTIONS               9
#define IP_MTU_DISCOVER             10
#define IP_RECVERR                  11
#define IP_RECVTTL                  12
#define IP_RECVTOS                  13
#define IP_MTU                      14
#define IP_FREEBIND                 15
#define IP_IPSEC_POLICY             16
#define IP_XFRM_POLICY              17
#define IP_PASSSEC                  18
#define IP_TRANSPARENT              19
#define IP_ORIGDSTADDR              20
#define IP_MINTTL                   21
#define IP_NODEFRAG                 22
#define IP_CHECKSUM                 23
#define IP_BIND_ADDRESS_NO_PORT     24
#define IP_RECVFRAGSIZE             25
#define IP_RECVERR_RFC4884          26
#define IP_MULTICAST_IF             32
#define IP_MULTICAST_TTL            33
#define IP_MULTICAST_LOOP           34
#define IP_ADD_MEMBERSHIP           35
#define IP_DROP_MEMBERSHIP          36
#define IP_UNBLOCK_SOURCE           37
#define IP_BLOCK_SOURCE             38
#define IP_ADD_SOURCE_MEMBERSHIP    39
#define IP_DROP_SOURCE_MEMBERSHIP   40
#define IP_MSFILTER                 41
#define IP_MULTICAST_ALL            49
#define IP_UNICAST_IF               50
#define IP_LOCAL_PORT_RANGE         51
#define IP_PROTOCOL                 52

/* IP_MTU_DISCOVER argument values, and the multicast defaults. Kept apart from
   the option numbers above because they share the same 0..5 range and mixing
   them into one sorted list is how a reader picks the wrong constant. */
#define IP_PMTUDISC_DONT            0
#define IP_PMTUDISC_WANT            1
#define IP_PMTUDISC_DO              2
#define IP_PMTUDISC_PROBE           3
#define IP_PMTUDISC_INTERFACE       4
#define IP_PMTUDISC_OMIT            5
#define IP_DEFAULT_MULTICAST_LOOP   1
#define IP_DEFAULT_MULTICAST_TTL    1

/* IPv6 ADDRESSES ARE TYPES HERE, NOT A CLAIM THAT v6 SOCKETS WORK. The socket
   layer under <sys/socket.h> parses AF_INET only -- getsockname on a v6 peer
   answers 0.0.0.0. These exist because programs that never open a v6 socket
   still need the struct: busybox's networking/route.c passes a struct
   in6_rtmsg to an ioctl, and libbb sizes its address union by the larger of
   the two. Declaring the type is what lets those compile honestly; a v6
   connect() still fails, which is the truthful outcome and not a silent one. */
struct in6_addr {
  union {
    uint8_t  __u6_addr8[16];
    uint16_t __u6_addr16[8];
    uint32_t __u6_addr32[4];
  } __in6_u;
};
#define s6_addr   __in6_u.__u6_addr8
#define s6_addr16 __in6_u.__u6_addr16
#define s6_addr32 __in6_u.__u6_addr32

struct sockaddr_in6 {
  sa_family_t sin6_family;
  in_port_t   sin6_port;
  uint32_t    sin6_flowinfo;
  struct in6_addr sin6_addr;
  uint32_t    sin6_scope_id;
};

extern const struct in6_addr in6addr_any;
extern const struct in6_addr in6addr_loopback;
#define IN6ADDR_ANY_INIT      { { { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } } }
#define IN6ADDR_LOOPBACK_INIT { { { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 } } }

#define INET_ADDRSTRLEN  16
#define INET6_ADDRSTRLEN 46

struct ipv6_mreq {
  struct in6_addr ipv6mr_multiaddr;
  unsigned int ipv6mr_interface;
};

struct ip_mreq {
  struct in_addr imr_multiaddr;
  struct in_addr imr_interface;
};

#endif
