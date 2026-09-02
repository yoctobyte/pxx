/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <netinet/ip_icmp.h>.
 *
 * TWO STRUCTS FOR ONE PACKET, again: `struct icmphdr' is Linux's eight-byte
 * header with a union for the last four bytes, and `struct icmp' is BSD's,
 * which folds the IP header of a quoted packet into the same declaration. Both
 * are here because glibc ships both and busybox's ping.c uses the Linux names
 * while its BSD arms use the others.
 *
 * ICMP_MINLEN IS 8, NOT sizeof(struct icmp). That is the whole reason the
 * constant exists: `struct icmp' is much larger than eight bytes because it
 * carries the quoted-packet variants, and a length check written as
 * sizeof(struct icmp) rejects every echo reply. glibc defines it as a literal
 * 8 for the same reason.
 *
 * Found attempting busybox rung 2: networking/ping.c.
 */
#ifndef _CRTL_NETINET_IP_ICMP_H
#define _CRTL_NETINET_IP_ICMP_H

#include <stdint.h>
#include <netinet/in.h>
#include <netinet/ip.h>

/* ---- Linux's spelling ----------------------------------------------------- */

struct icmphdr {
  uint8_t  type;
  uint8_t  code;
  uint16_t checksum;
  union {
    struct { uint16_t id; uint16_t sequence; } echo;
    uint32_t gateway;
    struct { uint16_t __unused_pad; uint16_t mtu; } frag;
  } un;
};

/* ---- BSD's spelling ------------------------------------------------------- */

struct icmp_ra_addr {
  uint32_t ira_addr;
  uint32_t ira_preference;
};

struct icmp {
  uint8_t  icmp_type;
  uint8_t  icmp_code;
  uint16_t icmp_cksum;
  union {
    unsigned char ih_pptr;
    struct in_addr ih_gwaddr;
    struct ih_idseq { uint16_t icd_id; uint16_t icd_seq; } ih_idseq;
    uint32_t ih_void;
    struct ih_pmtu { uint16_t ipm_void; uint16_t ipm_nextmtu; } ih_pmtu;
    struct ih_rtradv { uint8_t irt_num_addrs; uint8_t irt_wpa; uint16_t irt_lifetime; } ih_rtradv;
  } icmp_hun;
#define icmp_pptr       icmp_hun.ih_pptr
#define icmp_gwaddr     icmp_hun.ih_gwaddr
#define icmp_id         icmp_hun.ih_idseq.icd_id
#define icmp_seq        icmp_hun.ih_idseq.icd_seq
#define icmp_void       icmp_hun.ih_void
#define icmp_pmvoid     icmp_hun.ih_pmtu.ipm_void
#define icmp_nextmtu    icmp_hun.ih_pmtu.ipm_nextmtu
#define icmp_num_addrs  icmp_hun.ih_rtradv.irt_num_addrs
#define icmp_wpa        icmp_hun.ih_rtradv.irt_wpa
#define icmp_lifetime   icmp_hun.ih_rtradv.irt_lifetime
  union {
    struct { uint32_t its_otime; uint32_t its_rtime; uint32_t its_ttime; } id_ts;
    struct { struct ip idi_ip; /* options and then 64 bits of data */ } id_ip;
    struct icmp_ra_addr id_radv;
    uint32_t id_mask;
    char     id_data[1];
  } icmp_dun;
#define icmp_otime      icmp_dun.id_ts.its_otime
#define icmp_rtime      icmp_dun.id_ts.its_rtime
#define icmp_ttime      icmp_dun.id_ts.its_ttime
#define icmp_ip         icmp_dun.id_ip.idi_ip
#define icmp_radv       icmp_dun.id_radv
#define icmp_mask       icmp_dun.id_mask
#define icmp_data       icmp_dun.id_data
};

/* Eight bytes: type, code, checksum and the four-byte union. NOT
   sizeof(struct icmp) -- see the note at the top. */
#define ICMP_MINLEN 8
#define ICMP_TSLEN  (8 + 3 * sizeof(uint32_t))
#define ICMP_MASKLEN 12
#define ICMP_ADVLENMIN (8 + sizeof(struct ip) + 8)
#define ICMP_INFOTYPE(type) \
  ((type) == ICMP_ECHOREPLY || (type) == ICMP_ECHO || \
   (type) == ICMP_ROUTERADVERT || (type) == ICMP_ROUTERSOLICIT || \
   (type) == ICMP_TIMESTAMP || (type) == ICMP_TIMESTAMPREPLY || \
   (type) == ICMP_INFO_REQUEST || (type) == ICMP_INFO_REPLY || \
   (type) == ICMP_ADDRESS || (type) == ICMP_ADDRESSREPLY)

/* Message types. */
#define ICMP_ECHOREPLY       0
#define ICMP_DEST_UNREACH    3
#define ICMP_SOURCE_QUENCH   4
#define ICMP_REDIRECT        5
#define ICMP_ECHO            8
#define ICMP_ROUTERADVERT    9
#define ICMP_ROUTERSOLICIT  10
#define ICMP_TIME_EXCEEDED  11
#define ICMP_PARAMETERPROB  12
#define ICMP_TIMESTAMP      13
#define ICMP_TIMESTAMPREPLY 14
#define ICMP_INFO_REQUEST   15
#define ICMP_INFO_REPLY     16
#define ICMP_ADDRESS        17
#define ICMP_ADDRESSREPLY   18
#define NR_ICMP_TYPES       18

/* Codes for ICMP_DEST_UNREACH. */
#define ICMP_NET_UNREACH    0
#define ICMP_HOST_UNREACH   1
#define ICMP_PROT_UNREACH   2
#define ICMP_PORT_UNREACH   3
#define ICMP_FRAG_NEEDED    4
#define ICMP_SR_FAILED      5
#define ICMP_NET_UNKNOWN    6
#define ICMP_HOST_UNKNOWN   7
#define ICMP_HOST_ISOLATED  8
#define ICMP_NET_ANO        9
#define ICMP_HOST_ANO      10
#define ICMP_NET_UNR_TOS   11
#define ICMP_HOST_UNR_TOS  12
#define ICMP_PKT_FILTERED  13
#define ICMP_PREC_VIOLATION 14
#define ICMP_PREC_CUTOFF   15
#define NR_ICMP_UNREACH    15

/* Codes for ICMP_REDIRECT. */
#define ICMP_REDIR_NET     0
#define ICMP_REDIR_HOST    1
#define ICMP_REDIR_NETTOS  2
#define ICMP_REDIR_HOSTTOS 3

/* Codes for ICMP_TIME_EXCEEDED. */
#define ICMP_EXC_TTL      0
#define ICMP_EXC_FRAGTIME 1

#endif
