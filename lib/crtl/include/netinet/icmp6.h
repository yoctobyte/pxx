/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <netinet/icmp6.h>. ICMPv6 (RFC 4443), its socket filter
 * (RFC 3542) and IPv6 neighbour discovery (RFC 4861) in the BSD names that
 * glibc ships too. Added for dhcpcd's router-advertisement code (ipv6nd.c).
 *
 * THE FILTER IS LINUX'S SENSE: a SET bit BLOCKS that type (the kernel's
 * struct icmp6_filter), the reverse of the BSD kernels. The macros hide it;
 * a program that pokes icmp6_filt[] directly must know.
 *
 * Flag constants that sit in a 32-bit network-order word (nd_na_flags_reserved)
 * are given in the byte order of the targets crtl runs on, all little-endian.
 * The ones in a single byte (router-advert and prefix flags) need no swap.
 *
 * The route-information, RDNSS and DNSSL options (RFC 4191, 8106) are left
 * out, as glibc leaves them out: dhcpcd defines its own when these are absent.
 */
#ifndef _CRTL_NETINET_ICMP6_H
#define _CRTL_NETINET_ICMP6_H
#include <stdint.h>
#include <string.h>
#include <netinet/in.h>

#define ICMP6_FILTER 1   /* setsockopt(fd, IPPROTO_ICMPV6, ICMP6_FILTER, ...) */

struct icmp6_filter {
  uint32_t icmp6_filt[8];   /* 256 types; a set bit blocks the type (Linux) */
};
#define ICMP6_FILTER_SETPASSALL(f)  memset((f), 0, sizeof(struct icmp6_filter))
#define ICMP6_FILTER_SETBLOCKALL(f) memset((f), 0xff, sizeof(struct icmp6_filter))
#define ICMP6_FILTER_SETPASS(t, f)  \
  ((f)->icmp6_filt[(t) >> 5] &= ~((uint32_t)1 << ((t) & 31)))
#define ICMP6_FILTER_SETBLOCK(t, f) \
  ((f)->icmp6_filt[(t) >> 5] |= ((uint32_t)1 << ((t) & 31)))
#define ICMP6_FILTER_WILLPASS(t, f) \
  (((f)->icmp6_filt[(t) >> 5] & ((uint32_t)1 << ((t) & 31))) == 0)
#define ICMP6_FILTER_WILLBLOCK(t, f) \
  (((f)->icmp6_filt[(t) >> 5] & ((uint32_t)1 << ((t) & 31))) != 0)

struct icmp6_hdr {
  uint8_t  icmp6_type;
  uint8_t  icmp6_code;
  uint16_t icmp6_cksum;
  union {
    uint32_t icmp6_un_data32[1];
    uint16_t icmp6_un_data16[2];
    uint8_t  icmp6_un_data8[4];
  } icmp6_dataun;
};
#define icmp6_data32 icmp6_dataun.icmp6_un_data32
#define icmp6_data16 icmp6_dataun.icmp6_un_data16
#define icmp6_data8  icmp6_dataun.icmp6_un_data8
#define icmp6_pptr   icmp6_data32[0]
#define icmp6_mtu    icmp6_data32[0]
#define icmp6_id     icmp6_data16[0]
#define icmp6_seq    icmp6_data16[1]
#define icmp6_maxdelay icmp6_data16[0]

/* types (RFC 4443, 4861) */
#define ICMP6_DST_UNREACH        1
#define ICMP6_PACKET_TOO_BIG     2
#define ICMP6_TIME_EXCEEDED      3
#define ICMP6_PARAM_PROB         4
#define ICMP6_INFOMSG_MASK       0x80
#define ICMP6_ECHO_REQUEST       128
#define ICMP6_ECHO_REPLY         129
#define MLD_LISTENER_QUERY       130
#define MLD_LISTENER_REPORT      131
#define MLD_LISTENER_REDUCTION   132
#define ND_ROUTER_SOLICIT        133
#define ND_ROUTER_ADVERT         134
#define ND_NEIGHBOR_SOLICIT      135
#define ND_NEIGHBOR_ADVERT       136
#define ND_REDIRECT              137

/* codes */
#define ICMP6_DST_UNREACH_NOROUTE     0
#define ICMP6_DST_UNREACH_ADMIN       1
#define ICMP6_DST_UNREACH_BEYONDSCOPE 2
#define ICMP6_DST_UNREACH_ADDR        3
#define ICMP6_DST_UNREACH_NOPORT      4
#define ICMP6_TIME_EXCEED_TRANSIT     0
#define ICMP6_TIME_EXCEED_REASSEMBLY  1
#define ICMP6_PARAMPROB_HEADER        0
#define ICMP6_PARAMPROB_NEXTHEADER    1
#define ICMP6_PARAMPROB_OPTION        2

/* router solicitation: the bare header, options follow */
struct nd_router_solicit {
  struct icmp6_hdr nd_rs_hdr;
};
#define nd_rs_type     nd_rs_hdr.icmp6_type
#define nd_rs_code     nd_rs_hdr.icmp6_code
#define nd_rs_cksum    nd_rs_hdr.icmp6_cksum
#define nd_rs_reserved nd_rs_hdr.icmp6_data32[0]

/* router advertisement */
struct nd_router_advert {
  struct icmp6_hdr nd_ra_hdr;
  uint32_t nd_ra_reachable;    /* ms */
  uint32_t nd_ra_retransmit;   /* ms */
};
#define nd_ra_type            nd_ra_hdr.icmp6_type
#define nd_ra_code            nd_ra_hdr.icmp6_code
#define nd_ra_cksum           nd_ra_hdr.icmp6_cksum
#define nd_ra_curhoplimit     nd_ra_hdr.icmp6_data8[0]
#define nd_ra_flags_reserved  nd_ra_hdr.icmp6_data8[1]
#define nd_ra_router_lifetime nd_ra_hdr.icmp6_data16[1]   /* seconds */
#define ND_RA_FLAG_MANAGED    0x80
#define ND_RA_FLAG_OTHER      0x40
#define ND_RA_FLAG_HOME_AGENT 0x20

/* neighbour solicitation and advertisement */
struct nd_neighbor_solicit {
  struct icmp6_hdr nd_ns_hdr;
  struct in6_addr nd_ns_target;
};
#define nd_ns_type     nd_ns_hdr.icmp6_type
#define nd_ns_code     nd_ns_hdr.icmp6_code
#define nd_ns_cksum    nd_ns_hdr.icmp6_cksum
#define nd_ns_reserved nd_ns_hdr.icmp6_data32[0]

struct nd_neighbor_advert {
  struct icmp6_hdr nd_na_hdr;
  struct in6_addr nd_na_target;
};
#define nd_na_type           nd_na_hdr.icmp6_type
#define nd_na_code           nd_na_hdr.icmp6_code
#define nd_na_cksum          nd_na_hdr.icmp6_cksum
#define nd_na_flags_reserved nd_na_hdr.icmp6_data32[0]
/* the top three bits of the network-order word, as read little-endian */
#define ND_NA_FLAG_ROUTER    0x00000080
#define ND_NA_FLAG_SOLICITED 0x00000040
#define ND_NA_FLAG_OVERRIDE  0x00000020

struct nd_redirect {
  struct icmp6_hdr nd_rd_hdr;
  struct in6_addr nd_rd_target;
  struct in6_addr nd_rd_dst;
};
#define nd_rd_type     nd_rd_hdr.icmp6_type
#define nd_rd_code     nd_rd_hdr.icmp6_code
#define nd_rd_cksum    nd_rd_hdr.icmp6_cksum
#define nd_rd_reserved nd_rd_hdr.icmp6_data32[0]

/* options: type, then length in units of 8 bytes */
struct nd_opt_hdr {
  uint8_t nd_opt_type;
  uint8_t nd_opt_len;
};
#define ND_OPT_SOURCE_LINKADDR    1
#define ND_OPT_TARGET_LINKADDR    2
#define ND_OPT_PREFIX_INFORMATION 3
#define ND_OPT_REDIRECTED_HEADER  4
#define ND_OPT_MTU                5
#define ND_OPT_RTR_ADV_INTERVAL   7
#define ND_OPT_HOME_AGENT_INFO    8

struct nd_opt_prefix_info {   /* 32 bytes */
  uint8_t  nd_opt_pi_type;
  uint8_t  nd_opt_pi_len;
  uint8_t  nd_opt_pi_prefix_len;
  uint8_t  nd_opt_pi_flags_reserved;
  uint32_t nd_opt_pi_valid_time;
  uint32_t nd_opt_pi_preferred_time;
  uint32_t nd_opt_pi_reserved2;
  struct in6_addr nd_opt_pi_prefix;
};
#define ND_OPT_PI_FLAG_ONLINK 0x80
#define ND_OPT_PI_FLAG_AUTO   0x40

struct nd_opt_rd_hdr {
  uint8_t  nd_opt_rh_type;
  uint8_t  nd_opt_rh_len;
  uint16_t nd_opt_rh_reserved1;
  uint32_t nd_opt_rh_reserved2;
};

struct nd_opt_mtu {
  uint8_t  nd_opt_mtu_type;
  uint8_t  nd_opt_mtu_len;
  uint16_t nd_opt_mtu_reserved;
  uint32_t nd_opt_mtu_mtu;
};

#endif
