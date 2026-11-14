/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <ifaddrs.h> -- getifaddrs/freeifaddrs.
 *
 * IPv4 ONLY, from the SIOCGIFCONF ioctl. glibc builds the list from a netlink
 * dump, which also yields the IPv6 addresses and the AF_PACKET link entries;
 * a caller looking for an interface's IPv6 address finds none here. Found by
 * toybox's ping -I, which looks an interface name up in this list.
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
