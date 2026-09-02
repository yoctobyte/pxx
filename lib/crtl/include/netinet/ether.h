/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <netinet/ether.h> -- ethernet address <-> text.
 *
 * `struct ether_addr' itself lives in <net/ethernet.h> and is included from
 * there rather than repeated, for the reason <netinet/if_ether.h> gives: a
 * second copy of a wire layout is the one that drifts.
 *
 * ether_ntohost/ether_hostton/ether_line are NOT here. They read /etc/ethers,
 * which is a name-service question rather than a formatting one, and nothing
 * in the corpus calls them; declaring them without bodies would turn a missing
 * feature into an undefined symbol at link time, which is later and worse.
 *
 * Found attempting busybox on i386: 4 translation units stop here
 * (arp.c, arping.c, nameif.c, udhcp/dhcpd.c), and they use exactly two of
 * these -- ether_ntoa and ether_aton_r.
 * feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_NETINET_ETHER_H
#define _CRTL_NETINET_ETHER_H

#include <net/ethernet.h>

char *ether_ntoa(const struct ether_addr *addr);
char *ether_ntoa_r(const struct ether_addr *addr, char *buf);
struct ether_addr *ether_aton(const char *asc);
struct ether_addr *ether_aton_r(const char *asc, struct ether_addr *addr);

#endif
