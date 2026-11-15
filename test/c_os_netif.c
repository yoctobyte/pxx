/* Network interfaces under a translated --os (compiler/builtin/ifnet.inc):
   if_nameindex (from /proc/net/dev), if_nametoindex (SIOCGIFINDEX) and
   getifaddrs (SIOCGIFCONF, SIOCGIFFLAGS, SIOCGIFNETMASK) must find the
   loopback interface and 127.0.0.1 as on Linux. Prints only what is the
   same everywhere, for the test-<os> comparisons. */
#include <stdio.h>
#include <string.h>
#include <net/if.h>
#include <ifaddrs.h>
#include <sys/socket.h>
#include <netinet/in.h>
int main(void) {
  struct if_nameindex *ni = if_nameindex(), *p;
  struct ifaddrs *ia, *q;
  int n = 0, lo = 0, loidx = 0, v4lo = 0;
  if (!ni) printf("if_nameindex failed\n");
  else {
    for (p = ni; p->if_index; p++) { n++; if (strncmp(p->if_name, "lo", 2) == 0) { lo = 1; loidx = p->if_index; } }
    printf("nameindex: some %d, loopback %d\n", n > 0, lo);
    printf("nametoindex agrees %d\n", lo && if_nametoindex(ni[0].if_name) == ni[0].if_index);
    if_freenameindex(ni);
  }
  if (getifaddrs(&ia) != 0) printf("getifaddrs failed\n");
  else {
    for (q = ia; q; q = q->ifa_next)
      if (q->ifa_addr && q->ifa_addr->sa_family == AF_INET &&
          ((struct sockaddr_in *)q->ifa_addr)->sin_addr.s_addr == htonl(0x7f000001)) v4lo = 1;
    printf("getifaddrs: 127.0.0.1 listed %d\n", v4lo);
    freeifaddrs(ia);
  }
  return 0;
}
