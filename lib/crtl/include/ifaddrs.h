/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <ifaddrs.h> -- getifaddrs/freeifaddrs.
 *
 * As glibc builds the list, from two rtnetlink dumps: first one AF_PACKET
 * entry per interface (a sockaddr_ll with its index, ARPHRD type and hardware
 * address; the broadcast address; struct rtnl_link_stats in ifa_data), then
 * one entry per IPv4 and IPv6 address (netmask from the prefix length;
 * IFA_BROADCAST, or the peer on a point-to-point link; the scope id of a
 * link-local IPv6 address), every entry with its interface's full flags.
 * Until 2026-11-27 it was IPv4 only, from SIOCGIFCONF: dhcpcd, which builds
 * its interface list from the AF_PACKET entries, found no interface at all.
 */
#ifndef PXX_CRTL_IFADDRS_H
#define PXX_CRTL_IFADDRS_H 1

#include <sys/socket.h>

struct ifaddrs {
  struct ifaddrs  *ifa_next;
  char            *ifa_name;
  unsigned int     ifa_flags;
  struct sockaddr *ifa_addr;
  struct sockaddr *ifa_netmask;
  union {
    struct sockaddr *ifu_broadaddr;
    struct sockaddr *ifu_dstaddr;
  } ifa_ifu;
  void            *ifa_data;
};
#define ifa_broadaddr ifa_ifu.ifu_broadaddr
#define ifa_dstaddr   ifa_ifu.ifu_dstaddr

int getifaddrs(struct ifaddrs **ifap);
void freeifaddrs(struct ifaddrs *ifa);

#endif
