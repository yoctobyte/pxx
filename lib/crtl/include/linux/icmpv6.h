/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <linux/icmpv6.h>, the part a user program reads: the router
 * preference values of RFC 4191 (two bits of a router advertisement's flag
 * byte, and of the route-information option), with the kernel's names.
 * dhcpcd's if-linux.c. The kernel's own struct icmp6hdr is not here; programs
 * use <netinet/icmp6.h>'s struct icmp6_hdr.
 */
#ifndef _CRTL_LINUX_ICMPV6_H
#define _CRTL_LINUX_ICMPV6_H
#define ICMPV6_ROUTER_PREF_LOW     0x3
#define ICMPV6_ROUTER_PREF_MEDIUM  0x0
#define ICMPV6_ROUTER_PREF_HIGH    0x1
#define ICMPV6_ROUTER_PREF_INVALID 0x2
#endif
