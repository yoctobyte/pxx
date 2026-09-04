/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <netinet/ether.h> -- ethernet address <-> text.
 *
 * `struct ether_addr' itself lives in <net/ethernet.h> and is included from
 * there rather than repeated, for the reason <netinet/if_ether.h> gives: a
 * second copy of a wire layout is the one that drifts.
 *
 * ether_ntohost/ether_hostton/ether_line ARE here as of 2026-09-04, and the
 * paragraph that used to sit here is worth keeping as a worked example rather
 * than deleting. It read: "not here ... nothing in the corpus calls them;
 * declaring them without bodies would turn a missing feature into an undefined
 * symbol at link time, which is later and worse." Both halves were right when
 * written and the FIRST half went stale: at 394 applets
 * networking/ether-wake.c:134 calls ether_hostton. The second half is still
 * the rule and is why all three arrive WITH bodies.
 *
 * They read /etc/ethers, which is a name-service question rather than a
 * formatting one -- so, exactly as <grp.h> and <pwd.h> say of their own files,
 * this is the file and not NSS. A host that keeps ethers in LDAP resolves
 * nothing here, and that is the same answer glibc gives without nss_ldap.
 *
 * Found attempting busybox on i386: 4 translation units stop here
 * (arp.c, arping.c, nameif.c, udhcp/dhcpd.c), and they use exactly two of
 * these -- ether_ntoa and ether_aton_r.
 * feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_NETINET_ETHER_H
#define _CRTL_NETINET_ETHER_H

/* Via <netinet/if_ether.h> rather than <net/ethernet.h> directly, which is the
   chain glibc has and the one arping.c depends on: it includes THIS header and
   then names ARPHRD_ETHER, ARPOP_REQUEST and ETH_P_IP without including
   anything that would define them. Under glibc it compiles because this file
   pulls <netinet/if_ether.h>, which pulls <linux/if_ether.h> and
   <net/if_arp.h>. crtl stopped at <net/ethernet.h>, so all three became 0 with
   a warning and networking/arping.o went out with a zeroed ARP request in it. */
#include <netinet/if_ether.h>

char *ether_ntoa(const struct ether_addr *addr);
char *ether_ntoa_r(const struct ether_addr *addr, char *buf);
struct ether_addr *ether_aton(const char *asc);
struct ether_addr *ether_aton_r(const char *asc, struct ether_addr *addr);

/* /etc/ethers: `<ether-address> <hostname>', one per line, # to end of line.
   All three return 0 on success and -1 on failure -- NOT a pointer, and not an
   errno. ether_line parses one line and is the shared parser the other two run
   over the file, rather than three copies of the same tokeniser. */
int ether_line(const char *line, struct ether_addr *addr, char *hostname);
int ether_hostton(const char *hostname, struct ether_addr *addr);
int ether_ntohost(char *hostname, const struct ether_addr *addr);

#endif
