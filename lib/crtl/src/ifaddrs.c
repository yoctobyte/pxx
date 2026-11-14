/* SPDX-License-Identifier: Zlib */
/* C runtime: getifaddrs over SIOCGIFCONF (see <ifaddrs.h>). */
#include <ifaddrs.h>
#include <net/if.h>
#include <netinet/in.h>
#include <sys/ioctl.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>

struct crtl_ifa {
  struct ifaddrs ifa;
  struct sockaddr_in addr, mask, brd;
  char name[IFNAMSIZ + 1];
};

int getifaddrs(struct ifaddrs **ifap)
{
  struct ifconf ifc;
  struct ifreq *req;
  struct ifaddrs *head = 0, **tail = &head;
  int fd, n, i, cap = 32;

  *ifap = 0;
  fd = socket(AF_INET, SOCK_DGRAM | SOCK_CLOEXEC, 0);
  if (fd < 0) return -1;
  for (;;) {
    req = (struct ifreq *)malloc(sizeof(struct ifreq) * cap);
    if (!req) { close(fd); errno = ENOMEM; return -1; }
    ifc.ifc_len = (int)(sizeof(struct ifreq) * cap);
    ifc.ifc_req = req;
    if (ioctl(fd, SIOCGIFCONF, &ifc) < 0) { int e = errno; free(req); close(fd); errno = e; return -1; }
    /* a full buffer may have been truncated: grow and ask again */
    if (ifc.ifc_len < (int)(sizeof(struct ifreq) * cap)) break;
    free(req);
    cap *= 2;
  }
  n = ifc.ifc_len / (int)sizeof(struct ifreq);
  for (i = 0; i < n; i++) {
    struct crtl_ifa *e = (struct crtl_ifa *)calloc(1, sizeof *e);
    struct ifreq r;
    if (!e) { freeifaddrs(head); free(req); close(fd); errno = ENOMEM; return -1; }
    memcpy(e->name, req[i].ifr_name, IFNAMSIZ);
    e->ifa.ifa_name = e->name;
    memcpy(&e->addr, &req[i].ifr_addr, sizeof e->addr);
    e->ifa.ifa_addr = (struct sockaddr *)&e->addr;
    memset(&r, 0, sizeof r);
    memcpy(r.ifr_name, req[i].ifr_name, IFNAMSIZ);
    if (ioctl(fd, SIOCGIFFLAGS, &r) == 0) e->ifa.ifa_flags = (unsigned short)r.ifr_flags;
    if (ioctl(fd, SIOCGIFNETMASK, &r) == 0) {
      memcpy(&e->mask, &r.ifr_addr, sizeof e->mask);
      e->ifa.ifa_netmask = (struct sockaddr *)&e->mask;
    }
    if ((e->ifa.ifa_flags & IFF_BROADCAST) && ioctl(fd, SIOCGIFBRDADDR, &r) == 0) {
      memcpy(&e->brd, &r.ifr_addr, sizeof e->brd);
      e->ifa.ifa_broadaddr = (struct sockaddr *)&e->brd;
    }
    *tail = &e->ifa;
    tail = &e->ifa.ifa_next;
  }
  free(req);
  close(fd);
  *ifap = head;
  return 0;
}

void freeifaddrs(struct ifaddrs *ifa)
{
  while (ifa) {
    struct ifaddrs *nx = ifa->ifa_next;
    free(ifa);   /* the ifaddrs is the first member of its crtl_ifa block */
    ifa = nx;
  }
}
