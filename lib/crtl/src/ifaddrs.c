/* SPDX-License-Identifier: Zlib */
/* C runtime: getifaddrs over two rtnetlink dumps, as glibc builds it (see
   <ifaddrs.h>): RTM_GETLINK first, one AF_PACKET entry per interface, then
   RTM_GETADDR, one entry per IPv4 or IPv6 address, each in the kernel's dump
   order. */
#include <ifaddrs.h>
#include <net/if.h>
#include <netinet/in.h>
#include <netpacket/packet.h>
#include <linux/netlink.h>
#include <linux/rtnetlink.h>
#include <linux/if_link.h>
#include <linux/if_addr.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>

/* sockaddr_ll with room for a hardware address longer than Ethernet's (glibc
   keeps up to 24 bytes, InfiniBand's 20 among them) */
struct crtl_sockaddr_ll_max {
  unsigned short sll_family;
  unsigned short sll_protocol;
  int sll_ifindex;
  unsigned short sll_hatype;
  unsigned char sll_pkttype;
  unsigned char sll_halen;
  unsigned char sll_addr[24];
};

union crtl_ifa_sa {
  struct sockaddr sa;
  struct crtl_sockaddr_ll_max sl;
  struct sockaddr_in s4;
  struct sockaddr_in6 s6;
};

/* one block per entry: freeifaddrs frees it through its first member */
struct crtl_ifa {
  struct ifaddrs ifa;
  union crtl_ifa_sa addr, mask, brd;
  char name[IFNAMSIZ + 1];
  int index;                    /* a link entry's ifi_index */
  long long data[];             /* a link entry's IFLA_STATS */
};

/* one dump into *out (every message of it, concatenated) */
static int crtl_nl_dump(int fd, int type, int family, unsigned seq, char **out, size_t *outlen)
{
  struct { struct nlmsghdr nh; struct rtgenmsg g; char pad[3]; } req;
  char *all = 0, *buf;
  size_t len = 0, cap = 0;
  int bufsz = 65536;
  pid_t me = 0;

  memset(&req, 0, sizeof req);
  req.nh.nlmsg_len = NLMSG_LENGTH(sizeof(struct rtgenmsg));
  req.nh.nlmsg_type = (unsigned short)type;
  req.nh.nlmsg_flags = NLM_F_REQUEST | NLM_F_DUMP;
  req.nh.nlmsg_seq = seq;
  req.g.rtgen_family = (unsigned char)family;
  /* An unconnected netlink socket sends to the kernel: send(), not sendto()
     with a sockaddr_nl, because crtl's i386 sockets take only AF_INET
     addresses (netinet/in.c). On 64-bit the replies come through recvmsg,
     which says who sent each and whether it was cut; on the 32-bit targets
     through recv() (a dump message fits the 64 KiB buffer either way). */
  if (send(fd, &req, req.nh.nlmsg_len, 0) < 0) return -1;
#if defined(__SIZEOF_LONG__) && __SIZEOF_LONG__ == 8
  {
    struct sockaddr_nl self; socklen_t sl = sizeof self;
    if (getsockname(fd, (struct sockaddr *)&self, &sl) == 0) me = (pid_t)self.nl_pid;
  }
#endif
  buf = (char *)malloc((size_t)bufsz);
  if (!buf) { errno = ENOMEM; return -1; }
  for (;;) {
    struct nlmsghdr *nh;
    ssize_t n;
    int done = 0;
#if defined(__SIZEOF_LONG__) && __SIZEOF_LONG__ == 8
    struct sockaddr_nl from;
    struct iovec iov = { buf, (size_t)bufsz };
    struct msghdr m;
    memset(&m, 0, sizeof m);
    memset(&from, 0, sizeof from);
    m.msg_name = &from; m.msg_namelen = sizeof from;
    m.msg_iov = &iov; m.msg_iovlen = 1;
    n = recvmsg(fd, &m, 0);
    if (n < 0) { if (errno == EINTR) continue; goto fail; }
    if (m.msg_flags & MSG_TRUNC) { errno = ENOBUFS; goto fail; }
    if (from.nl_pid != 0) continue;                   /* not the kernel */
#else
    n = recv(fd, buf, (size_t)bufsz, 0);
    if (n < 0) { if (errno == EINTR) continue; goto fail; }
#endif
    for (nh = (struct nlmsghdr *)buf; NLMSG_OK(nh, (unsigned)n); nh = NLMSG_NEXT(nh, n)) {
      if (nh->nlmsg_seq != seq || (me && nh->nlmsg_pid != (unsigned)me)) continue;
      if (nh->nlmsg_type == NLMSG_DONE) { done = 1; break; }
      if (nh->nlmsg_type == NLMSG_ERROR) {
        struct nlmsgerr *e = (struct nlmsgerr *)NLMSG_DATA(nh);
        errno = nh->nlmsg_len >= NLMSG_LENGTH(sizeof *e) && e->error ? -e->error : EIO;
        goto fail;
      }
      if (len + NLMSG_ALIGN(nh->nlmsg_len) > cap) {
        size_t nc = cap ? cap * 2 : 65536;
        char *na;
        while (nc < len + NLMSG_ALIGN(nh->nlmsg_len)) nc *= 2;
        na = (char *)realloc(all, nc);
        if (!na) { errno = ENOMEM; goto fail; }
        all = na; cap = nc;
      }
      memcpy(all + len, nh, nh->nlmsg_len);
      len += NLMSG_ALIGN(nh->nlmsg_len);
    }
    if (done) break;
  }
  free(buf);
  *out = all;
  *outlen = len;
  return 0;
fail:
  free(buf);
  free(all);
  return -1;
}

static void crtl_ifa_ip(union crtl_ifa_sa *sa, int family, const void *p, size_t n, int index)
{
  sa->sa.sa_family = (unsigned short)family;
  if (family == AF_INET) {
    if (n == 4) memcpy(&sa->s4.sin_addr, p, 4);
  } else if (family == AF_INET6) {
    if (n == 16) {
      memcpy(&sa->s6.sin6_addr, p, 16);
      if (IN6_IS_ADDR_LINKLOCAL(&sa->s6.sin6_addr) || IN6_IS_ADDR_MC_LINKLOCAL(&sa->s6.sin6_addr))
        sa->s6.sin6_scope_id = (unsigned)index;
    }
  } else if (n <= sizeof *sa - sizeof sa->sa.sa_family) {
    memcpy(sa->sa.sa_data, p, n);
  }
}

/* Where the OS has no netlink (the BSD, Minix and NT translators): the IPv4
   addresses from SIOCGIFCONF, with their flags, netmask and broadcast
   address, which is what getifaddrs was before it used netlink. On Linux this
   is never reached: AF_NETLINK always exists there. */
static int crtl_getifaddrs_ioctl(struct ifaddrs **ifap)
{
  struct ifconf ifc;
  struct ifreq *req;
  struct ifaddrs *head = 0, **tail = &head;
  int fd, n, i, cap = 32;

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
    memcpy(&e->addr.s4, &req[i].ifr_addr, sizeof e->addr.s4);
    e->ifa.ifa_addr = &e->addr.sa;
    memset(&r, 0, sizeof r);
    memcpy(r.ifr_name, req[i].ifr_name, IFNAMSIZ);
    if (ioctl(fd, SIOCGIFFLAGS, &r) == 0) e->ifa.ifa_flags = (unsigned short)r.ifr_flags;
    if (ioctl(fd, SIOCGIFNETMASK, &r) == 0) {
      memcpy(&e->mask.s4, &r.ifr_addr, sizeof e->mask.s4);
      e->ifa.ifa_netmask = &e->mask.sa;
    }
    if ((e->ifa.ifa_flags & IFF_BROADCAST) && ioctl(fd, SIOCGIFBRDADDR, &r) == 0) {
      memcpy(&e->brd.s4, &r.ifr_addr, sizeof e->brd.s4);
      e->ifa.ifa_broadaddr = &e->brd.sa;
    }
    *tail = &e->ifa;
    tail = &e->ifa.ifa_next;
  }
  free(req);
  close(fd);
  *ifap = head;
  return 0;
}

int getifaddrs(struct ifaddrs **ifap)
{
  struct ifaddrs *head = 0, **tail = &head;
  struct crtl_ifa **links = 0;
  int nlinks = 0, caplinks = 0;
  char *lbuf = 0, *abuf = 0;
  size_t llen = 0, alen = 0, off;
  int fd, e;

  *ifap = 0;
  fd = socket(AF_NETLINK, SOCK_RAW | SOCK_CLOEXEC, NETLINK_ROUTE);
  if (fd < 0) {
    if (errno == EAFNOSUPPORT || errno == EPROTONOSUPPORT) return crtl_getifaddrs_ioctl(ifap);
    return -1;
  }
  if (crtl_nl_dump(fd, RTM_GETLINK, AF_PACKET, 1, &lbuf, &llen) < 0 ||
      crtl_nl_dump(fd, RTM_GETADDR, AF_UNSPEC, 2, &abuf, &alen) < 0)
    goto fail;

  /* the interfaces */
  for (off = 0; off < llen; ) {
    struct nlmsghdr *nh = (struct nlmsghdr *)(lbuf + off);
    struct ifinfomsg *ifi = (struct ifinfomsg *)NLMSG_DATA(nh);
    struct rtattr *a;
    int alen2;
    size_t stats = 0;
    struct crtl_ifa *x;
    off += NLMSG_ALIGN(nh->nlmsg_len);
    if (nh->nlmsg_type != RTM_NEWLINK) continue;
    alen2 = (int)IFLA_PAYLOAD(nh);
    for (a = IFLA_RTA(ifi); RTA_OK(a, alen2); a = RTA_NEXT(a, alen2))
      if (a->rta_type == IFLA_STATS) stats = RTA_PAYLOAD(a);
    x = (struct crtl_ifa *)calloc(1, sizeof *x + stats);
    if (!x) { errno = ENOMEM; goto fail; }
    x->ifa.ifa_flags = ifi->ifi_flags;
    x->index = ifi->ifi_index;
    alen2 = (int)IFLA_PAYLOAD(nh);
    for (a = IFLA_RTA(ifi); RTA_OK(a, alen2); a = RTA_NEXT(a, alen2)) {
      size_t n = RTA_PAYLOAD(a);
      union crtl_ifa_sa *sa = 0;
      if (a->rta_type == IFLA_ADDRESS) sa = &x->addr;
      else if (a->rta_type == IFLA_BROADCAST) sa = &x->brd;
      if (sa) {
        if (n <= sizeof sa->sl.sll_addr) {
          memcpy(sa->sl.sll_addr, RTA_DATA(a), n);
          sa->sl.sll_halen = (unsigned char)n;
          sa->sl.sll_ifindex = ifi->ifi_index;
          sa->sl.sll_hatype = ifi->ifi_type;
          sa->sl.sll_family = AF_PACKET;
          if (sa == &x->addr) x->ifa.ifa_addr = &sa->sa;
          else x->ifa.ifa_broadaddr = &sa->sa;
        }
      } else if (a->rta_type == IFLA_IFNAME) {
        if (n > IFNAMSIZ + 1) n = IFNAMSIZ + 1;
        memcpy(x->name, RTA_DATA(a), n);
        x->name[IFNAMSIZ] = 0;
        x->ifa.ifa_name = x->name;
      } else if (a->rta_type == IFLA_STATS) {
        memcpy(x->data, RTA_DATA(a), n);
        x->ifa.ifa_data = x->data;
      }
    }
    if (!x->ifa.ifa_name) x->ifa.ifa_name = x->name;
    if (nlinks == caplinks) {
      int nc = caplinks ? caplinks * 2 : 16;
      struct crtl_ifa **nl = (struct crtl_ifa **)realloc(links, sizeof *links * (size_t)nc);
      if (!nl) { free(x); errno = ENOMEM; goto fail; }
      links = nl; caplinks = nc;
    }
    links[nlinks++] = x;
    *tail = &x->ifa;
    tail = &x->ifa.ifa_next;
  }

  /* the addresses */
  for (off = 0; off < alen; ) {
    struct nlmsghdr *nh = (struct nlmsghdr *)(abuf + off);
    struct ifaddrmsg *ifam = (struct ifaddrmsg *)NLMSG_DATA(nh);
    struct crtl_ifa *x, *link = 0;
    struct rtattr *a;
    int alen2, i;
    off += NLMSG_ALIGN(nh->nlmsg_len);
    if (nh->nlmsg_type != RTM_NEWADDR) continue;
    for (i = 0; i < nlinks; i++)
      if (links[i]->index == (int)ifam->ifa_index) { link = links[i]; break; }
    if (!link) continue;          /* an address on a link the first dump did not list */
    x = (struct crtl_ifa *)calloc(1, sizeof *x);
    if (!x) { errno = ENOMEM; goto fail; }
    x->ifa.ifa_flags = link->ifa.ifa_flags;
    alen2 = (int)IFA_PAYLOAD(nh);
    for (a = IFA_RTA(ifam); RTA_OK(a, alen2); a = RTA_NEXT(a, alen2)) {
      size_t n = RTA_PAYLOAD(a);
      switch (a->rta_type) {
      case IFA_ADDRESS:
        /* after IFA_LOCAL it is the peer of a point-to-point link */
        if (x->ifa.ifa_addr) {
          crtl_ifa_ip(&x->brd, ifam->ifa_family, RTA_DATA(a), n, (int)ifam->ifa_index);
          x->ifa.ifa_broadaddr = &x->brd.sa;
        } else {
          crtl_ifa_ip(&x->addr, ifam->ifa_family, RTA_DATA(a), n, (int)ifam->ifa_index);
          x->ifa.ifa_addr = &x->addr.sa;
        }
        break;
      case IFA_LOCAL:
        /* this end: what IFA_ADDRESS gave first was the peer */
        if (x->ifa.ifa_addr) {
          x->brd = x->addr;
          x->ifa.ifa_broadaddr = &x->brd.sa;
          memset(&x->addr, 0, sizeof x->addr);
        }
        crtl_ifa_ip(&x->addr, ifam->ifa_family, RTA_DATA(a), n, (int)ifam->ifa_index);
        x->ifa.ifa_addr = &x->addr.sa;
        break;
      case IFA_BROADCAST:
        if (x->ifa.ifa_broadaddr) memset(&x->brd, 0, sizeof x->brd);
        crtl_ifa_ip(&x->brd, ifam->ifa_family, RTA_DATA(a), n, (int)ifam->ifa_index);
        x->ifa.ifa_broadaddr = &x->brd.sa;
        break;
      case IFA_LABEL:
        if (n + 1 <= sizeof x->name) {
          memcpy(x->name, RTA_DATA(a), n);
          x->name[n] = 0;
          x->ifa.ifa_name = x->name;
        }
        break;
      }
    }
    if (!x->ifa.ifa_name) x->ifa.ifa_name = link->ifa.ifa_name;
    if (x->ifa.ifa_addr && x->ifa.ifa_addr->sa_family != AF_UNSPEC && x->ifa.ifa_addr->sa_family != AF_PACKET) {
      unsigned max = ifam->ifa_family == AF_INET ? 32 : 128, plen = ifam->ifa_prefixlen, b;
      unsigned char *m;
      if (plen > max) plen = max;
      x->mask.sa.sa_family = ifam->ifa_family;
      m = ifam->ifa_family == AF_INET ? (unsigned char *)&x->mask.s4.sin_addr
          : ifam->ifa_family == AF_INET6 ? (unsigned char *)&x->mask.s6.sin6_addr
          : (unsigned char *)x->mask.sa.sa_data;
      for (b = 0; b < plen / 8; b++) m[b] = 0xff;
      if (plen % 8) m[b] = (unsigned char)(0xff << (8 - plen % 8));
      x->ifa.ifa_netmask = &x->mask.sa;
    }
    *tail = &x->ifa;
    tail = &x->ifa.ifa_next;
  }
  free(links);
  free(lbuf);
  free(abuf);
  close(fd);
  *ifap = head;
  return 0;
fail:
  e = errno;
  free(links);
  free(lbuf);
  free(abuf);
  freeifaddrs(head);
  close(fd);
  errno = e;
  return -1;
}

void freeifaddrs(struct ifaddrs *ifa)
{
  while (ifa) {
    struct ifaddrs *nx = ifa->ifa_next;
    free(ifa);   /* the ifaddrs is the first member of its crtl_ifa block */
    ifa = nx;
  }
}
