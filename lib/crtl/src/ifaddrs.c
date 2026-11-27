/* SPDX-License-Identifier: Zlib */
/* C runtime: getifaddrs (see <ifaddrs.h>).

   FROM NETLINK, as glibc and musl do: one RTM_GETLINK dump gives every
   interface an AF_PACKET entry (its hardware address in a sockaddr_ll, its
   flags, its rtnl_link_stats in ifa_data), up or down, addressed or not. Then
   one RTM_GETADDR dump gives an AF_INET or AF_INET6 entry per address.
   SIOCGIFCONF, which this used before, lists only interfaces that already
   HAVE an IPv4 address. So a DHCP client looking for the fresh eth0 it is
   about to configure did not find it: dhcpcd on Rainyday said "eth0:
   interface not found" (bug-c-crtl-getifaddrs-misses-an-interface-without-an-address).
   SIOCGIFCONF stays as the fallback when no netlink socket can be opened. */
#include <ifaddrs.h>
#include <net/if.h>
#include <netinet/in.h>
#include <netpacket/packet.h>
#include <linux/netlink.h>
#include <linux/rtnetlink.h>
#include <linux/if_link.h>
#include <linux/if_addr.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>

/* One block per entry: freeifaddrs frees it through its first member. */
struct crtl_ifa {
  struct ifaddrs ifa;
  union { struct sockaddr sa; struct sockaddr_in in; struct sockaddr_in6 in6; struct sockaddr_ll ll; } addr, mask, brd;
  char name[IFNAMSIZ + 1];
  struct rtnl_link_stats stats;
};

/* ---- the SIOCGIFCONF fallback (IPv4 addresses only) ---- */
static int crtl_ifaddrs_ioctl(struct ifaddrs **ifap)
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
    memcpy(&e->addr.in, &req[i].ifr_addr, sizeof e->addr.in);
    e->ifa.ifa_addr = &e->addr.sa;
    memset(&r, 0, sizeof r);
    memcpy(r.ifr_name, req[i].ifr_name, IFNAMSIZ);
    if (ioctl(fd, SIOCGIFFLAGS, &r) == 0) e->ifa.ifa_flags = (unsigned short)r.ifr_flags;
    if (ioctl(fd, SIOCGIFNETMASK, &r) == 0) {
      memcpy(&e->mask.in, &r.ifr_addr, sizeof e->mask.in);
      e->ifa.ifa_netmask = &e->mask.sa;
    }
    if ((e->ifa.ifa_flags & IFF_BROADCAST) && ioctl(fd, SIOCGIFBRDADDR, &r) == 0) {
      memcpy(&e->brd.in, &r.ifr_addr, sizeof e->brd.in);
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

/* ---- netlink ---- */

/* the interfaces the link dump reported, so an address can name its interface */
struct crtl_iflink { int index; unsigned int flags; char name[IFNAMSIZ + 1]; };

struct crtl_ifa_state {
  struct ifaddrs *head, **tail;
  struct crtl_iflink *links;
  int nlinks, caplinks;
};

static struct crtl_iflink *crtl_ifa_link(struct crtl_ifa_state *st, int index)
{
  int i;
  for (i = 0; i < st->nlinks; i++)
    if (st->links[i].index == index) return &st->links[i];
  return 0;
}

static void crtl_ifa_append(struct crtl_ifa_state *st, struct crtl_ifa *e)
{
  *st->tail = &e->ifa;
  st->tail = &e->ifa.ifa_next;
}

static int crtl_ifa_newlink(struct crtl_ifa_state *st, struct nlmsghdr *h)
{
  struct ifinfomsg *ifi = (struct ifinfomsg *)NLMSG_DATA(h);
  struct rtattr *rta = IFLA_RTA(ifi);
  int len = (int)IFLA_PAYLOAD(h);
  struct crtl_ifa *e = (struct crtl_ifa *)calloc(1, sizeof *e);
  struct crtl_iflink *l;
  if (!e) return -1;
  e->ifa.ifa_name = e->name;
  e->ifa.ifa_flags = ifi->ifi_flags;
  e->addr.ll.sll_family = AF_PACKET;
  e->addr.ll.sll_ifindex = ifi->ifi_index;
  e->addr.ll.sll_hatype = ifi->ifi_type;
  e->brd.ll = e->addr.ll;
  for (; RTA_OK(rta, len); rta = RTA_NEXT(rta, len)) {
    unsigned int n = RTA_PAYLOAD(rta);
    switch (rta->rta_type) {
    case IFLA_IFNAME:
      if (n > IFNAMSIZ) n = IFNAMSIZ;
      memcpy(e->name, RTA_DATA(rta), n);
      e->name[IFNAMSIZ] = 0;
      break;
    case IFLA_ADDRESS:
      if (n > sizeof e->addr.ll.sll_addr) n = sizeof e->addr.ll.sll_addr;
      memcpy(e->addr.ll.sll_addr, RTA_DATA(rta), n);
      e->addr.ll.sll_halen = (unsigned char)n;
      e->ifa.ifa_addr = &e->addr.sa;   /* none without one (a tun), as glibc */
      break;
    case IFLA_BROADCAST:
      if (n > sizeof e->brd.ll.sll_addr) n = sizeof e->brd.ll.sll_addr;
      memcpy(e->brd.ll.sll_addr, RTA_DATA(rta), n);
      e->brd.ll.sll_halen = (unsigned char)n;
      e->ifa.ifa_broadaddr = &e->brd.sa;
      break;
    case IFLA_STATS:
      if (n > sizeof e->stats) n = sizeof e->stats;
      memcpy(&e->stats, RTA_DATA(rta), n);
      e->ifa.ifa_data = &e->stats;
      break;
    }
  }
  if (st->nlinks == st->caplinks) {
    int cap = st->caplinks ? st->caplinks * 2 : 16;
    struct crtl_iflink *nl = (struct crtl_iflink *)realloc(st->links, sizeof *nl * (size_t)cap);
    if (!nl) { free(e); return -1; }
    st->links = nl;
    st->caplinks = cap;
  }
  l = &st->links[st->nlinks++];
  l->index = ifi->ifi_index;
  l->flags = ifi->ifi_flags;
  memcpy(l->name, e->name, sizeof l->name);
  crtl_ifa_append(st, e);
  return 0;
}

/* a prefix length as a netmask in `sa', of `family' */
static void crtl_ifa_mask(struct crtl_ifa *e, int family, unsigned int plen)
{
  unsigned char *p;
  unsigned int i, max;
  if (family == AF_INET) { e->mask.in.sin_family = AF_INET; p = (unsigned char *)&e->mask.in.sin_addr; max = 32; }
  else { e->mask.in6.sin6_family = AF_INET6; p = (unsigned char *)&e->mask.in6.sin6_addr; max = 128; }
  if (plen > max) plen = max;
  for (i = 0; i < plen / 8; i++) p[i] = 0xff;
  if (plen % 8) p[i] = (unsigned char)(0xff << (8 - plen % 8));
  e->ifa.ifa_netmask = &e->mask.sa;
}

static void crtl_ifa_put(union { struct sockaddr sa; struct sockaddr_in in; struct sockaddr_in6 in6; struct sockaddr_ll ll; } *u,
                         int family, const void *data, unsigned int n, int index)
{
  if (family == AF_INET && n >= 4) {
    u->in.sin_family = AF_INET;
    memcpy(&u->in.sin_addr, data, 4);
  } else if (family == AF_INET6 && n >= 16) {
    u->in6.sin6_family = AF_INET6;
    memcpy(&u->in6.sin6_addr, data, 16);
    /* a link-local or interface-local address is only meaningful with its scope */
    if ((u->in6.sin6_addr.s6_addr[0] == 0xfe && (u->in6.sin6_addr.s6_addr[1] & 0xc0) == 0x80) ||
        (u->in6.sin6_addr.s6_addr[0] == 0xff && (u->in6.sin6_addr.s6_addr[1] & 0x0f) <= 2))
      u->in6.sin6_scope_id = (unsigned int)index;
  }
}

static int crtl_ifa_newaddr(struct crtl_ifa_state *st, struct nlmsghdr *h)
{
  struct ifaddrmsg *ifa = (struct ifaddrmsg *)NLMSG_DATA(h);
  struct rtattr *rta = IFA_RTA(ifa);
  int len = (int)IFA_PAYLOAD(h);
  struct crtl_iflink *l;
  struct crtl_ifa *e;
  const void *address = 0, *local = 0, *brd = 0;
  unsigned int naddress = 0, nlocal = 0, nbrd = 0;
  const char *label = 0;
  unsigned int nlabel = 0;
  if (ifa->ifa_family != AF_INET && ifa->ifa_family != AF_INET6) return 0;
  for (; RTA_OK(rta, len); rta = RTA_NEXT(rta, len)) {
    switch (rta->rta_type) {
    case IFA_ADDRESS:   address = RTA_DATA(rta); naddress = RTA_PAYLOAD(rta); break;
    case IFA_LOCAL:     local = RTA_DATA(rta);   nlocal = RTA_PAYLOAD(rta);   break;
    case IFA_BROADCAST: brd = RTA_DATA(rta);     nbrd = RTA_PAYLOAD(rta);     break;
    case IFA_LABEL:     label = (const char *)RTA_DATA(rta); nlabel = RTA_PAYLOAD(rta); break;
    }
  }
  if (!address && !local) return 0;
  e = (struct crtl_ifa *)calloc(1, sizeof *e);
  if (!e) return -1;
  l = crtl_ifa_link(st, (int)ifa->ifa_index);
  if (ifa->ifa_family == AF_INET && label && nlabel > 0) {
    /* an IPv4 alias (eth0:1) is named by its label, as glibc does */
    if (nlabel > IFNAMSIZ) nlabel = IFNAMSIZ;
    memcpy(e->name, label, nlabel);
  } else if (l) {
    memcpy(e->name, l->name, sizeof e->name);
  }
  e->name[IFNAMSIZ] = 0;
  e->ifa.ifa_name = e->name;
  e->ifa.ifa_flags = l ? l->flags : 0;
  /* IFA_LOCAL is the address; IFA_ADDRESS is the peer on a point-to-point link */
  if (local) {
    crtl_ifa_put(&e->addr, ifa->ifa_family, local, nlocal, (int)ifa->ifa_index);
    if (address && (nlocal != naddress || memcmp(local, address, nlocal) != 0)) {
      crtl_ifa_put(&e->brd, ifa->ifa_family, address, naddress, (int)ifa->ifa_index);
      e->ifa.ifa_dstaddr = &e->brd.sa;
    }
  } else {
    crtl_ifa_put(&e->addr, ifa->ifa_family, address, naddress, (int)ifa->ifa_index);
  }
  e->ifa.ifa_addr = &e->addr.sa;
  if (brd && !e->ifa.ifa_dstaddr) {
    crtl_ifa_put(&e->brd, ifa->ifa_family, brd, nbrd, (int)ifa->ifa_index);
    e->ifa.ifa_broadaddr = &e->brd.sa;
  }
  crtl_ifa_mask(e, ifa->ifa_family, ifa->ifa_prefixlen);
  crtl_ifa_append(st, e);
  return 0;
}

/* one dump request; every reply message to `fn'. 0, or -1 with errno */
static int crtl_ifa_dump(int fd, int type, unsigned int seq, struct crtl_ifa_state *st)
{
  struct { struct nlmsghdr nh; struct rtgenmsg g; } req;
  struct sockaddr_nl to;
  char *buf;
  const int cap = 16384;
  memset(&req, 0, sizeof req);
  req.nh.nlmsg_len = NLMSG_LENGTH(sizeof req.g);
  req.nh.nlmsg_type = (unsigned short)type;
  req.nh.nlmsg_flags = NLM_F_REQUEST | NLM_F_DUMP;
  req.nh.nlmsg_seq = seq;
  req.g.rtgen_family = AF_UNSPEC;
  memset(&to, 0, sizeof to);
  to.nl_family = AF_NETLINK;
  if (sendto(fd, &req, req.nh.nlmsg_len, 0, (struct sockaddr *)&to, sizeof to) < 0) return -1;
  buf = (char *)malloc((size_t)cap);
  if (!buf) { errno = ENOMEM; return -1; }
  for (;;) {
    ssize_t n = recv(fd, buf, (size_t)cap, 0);
    struct nlmsghdr *h;
    int len;
    if (n < 0) { if (errno == EINTR) continue; free(buf); return -1; }
    if (n == 0) { free(buf); errno = EIO; return -1; }
    len = (int)n;
    for (h = (struct nlmsghdr *)buf; NLMSG_OK(h, len); h = NLMSG_NEXT(h, len)) {
      if (h->nlmsg_seq != seq) continue;
      if (h->nlmsg_type == NLMSG_DONE) { free(buf); return 0; }
      if (h->nlmsg_type == NLMSG_ERROR) {
        struct nlmsgerr *er = (struct nlmsgerr *)NLMSG_DATA(h);
        free(buf);
        errno = er->error ? -er->error : EIO;
        return -1;
      }
      if (h->nlmsg_type == RTM_NEWLINK) { if (crtl_ifa_newlink(st, h) < 0) { free(buf); errno = ENOMEM; return -1; } }
      else if (h->nlmsg_type == RTM_NEWADDR) { if (crtl_ifa_newaddr(st, h) < 0) { free(buf); errno = ENOMEM; return -1; } }
    }
  }
}

int getifaddrs(struct ifaddrs **ifap)
{
  struct crtl_ifa_state st;
  struct sockaddr_nl me;
  int fd, e;

  *ifap = 0;
  fd = socket(AF_NETLINK, SOCK_RAW | SOCK_CLOEXEC, NETLINK_ROUTE);
  if (fd < 0) return crtl_ifaddrs_ioctl(ifap);
  memset(&me, 0, sizeof me);
  me.nl_family = AF_NETLINK;
  if (bind(fd, (struct sockaddr *)&me, sizeof me) < 0) { close(fd); return crtl_ifaddrs_ioctl(ifap); }
  memset(&st, 0, sizeof st);
  st.tail = &st.head;
  if (crtl_ifa_dump(fd, RTM_GETLINK, 1, &st) < 0 || crtl_ifa_dump(fd, RTM_GETADDR, 2, &st) < 0) {
    e = errno;
    close(fd);
    free(st.links);
    freeifaddrs(st.head);
    errno = e;
    return -1;
  }
  close(fd);
  free(st.links);
  *ifap = st.head;
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
