/* SPDX-License-Identifier: Zlib */
/* getifaddrs, against glibc's on the same host: the same entries in the same
   order, one AF_PACKET entry per interface (its sockaddr_ll: index, ARPHRD
   type, hardware address and broadcast address; and the link statistics in
   ifa_data), then each IPv4 and IPv6 address (with its netmask, broadcast or
   point-to-point peer, IPv6 scope id), every entry with its interface's
   full flags, IFF_LOWER_UP included. dhcpcd builds its interface list from
   the AF_PACKET entries: with only the IPv4 ones (crtl's SIOCGIFCONF list,
   before) it found no interface. The counters in ifa_data move between the
   two runs, so only their presence is compared. */
#define _GNU_SOURCE 1
#include <stdio.h>
#include <string.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netpacket/packet.h>
#include <arpa/inet.h>

static void sa(const char *what, const struct sockaddr *s)
{
  char b[64];
  int i;
  if (!s) { printf(" %s=-", what); return; }
  switch (s->sa_family) {
  case AF_INET:
    inet_ntop(AF_INET, &((const struct sockaddr_in *)s)->sin_addr, b, sizeof b);
    printf(" %s=%s", what, b);
    break;
  case AF_INET6: {
    const struct sockaddr_in6 *s6 = (const struct sockaddr_in6 *)s;
    inet_ntop(AF_INET6, &s6->sin6_addr, b, sizeof b);
    printf(" %s=%s%%%u", what, b, s6->sin6_scope_id);
    break;
  }
  case AF_PACKET: {
    const struct sockaddr_ll *l = (const struct sockaddr_ll *)s;
    printf(" %s=ll(if%d type%u len%u", what, l->sll_ifindex, l->sll_hatype, l->sll_halen);
    for (i = 0; i < l->sll_halen && i < 8; i++) printf("%c%02x", i ? ':' : ' ', l->sll_addr[i]);
    printf(")");
    break;
  }
  default:
    printf(" %s=family%d", what, s->sa_family);
  }
}

int main(void)
{
  struct ifaddrs *ifa, *i;
  int n = 0, links = 0, v4 = 0, v6 = 0;
  if (getifaddrs(&ifa) != 0) { perror("getifaddrs"); return 1; }
  for (i = ifa; i; i = i->ifa_next) {
    int fam = i->ifa_addr ? i->ifa_addr->sa_family : -1;
    n++;
    links += fam == AF_PACKET || (fam == -1 && i->ifa_data);
    v4 += fam == AF_INET;
    v6 += fam == AF_INET6;
    printf("%s flags=%#x", i->ifa_name, i->ifa_flags);
    sa("addr", i->ifa_addr);
    sa("mask", i->ifa_netmask);
    sa((i->ifa_flags & IFF_POINTOPOINT) ? "dst" : "brd", i->ifa_broadaddr);
    printf(" data=%s\n", i->ifa_data ? "y" : "n");
  }
  freeifaddrs(ifa);
  printf("%d entries: %d interfaces, %d IPv4, %d IPv6\n", n, links, v4, v6);
  printf("lo index: %u\n", if_nametoindex("lo"));
  return 0;
}
