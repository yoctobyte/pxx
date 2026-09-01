/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <net/if.h> -- name/index mapping.
 *
 * All three go through a socket, because that is where the kernel keeps the
 * interface table: there is no syscall that answers "what index is eth0", only
 * an ioctl on an open socket. AF_INET/SOCK_DGRAM is the conventional carrier
 * and needs no address; the socket is closed again before returning.
 *
 * if_nameindex reads /proc/net/dev rather than issuing SIOCGIFCONF. THE TWO
 * ANSWER DIFFERENT QUESTIONS: SIOCGIFCONF lists interfaces that have an IPv4
 * address, so a down interface, or an IPv6-only one, is simply absent from its
 * reply -- with no error to say so. /proc/net/dev lists every registered
 * device, which is what the function promises. (glibc uses netlink for the
 * same reason; this runtime has no netlink socket yet, and /proc is the other
 * complete source.)
 *
 * Found attempting busybox rung 2: libbb/xconnect.c, networking/ifconfig.c.
 */
#include <net/if.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <errno.h>

/* A datagram socket to carry the ioctl. -1 with errno set on failure. */
static int if_sock(void) {
  return socket(AF_INET, SOCK_DGRAM, 0);
}

unsigned int if_nametoindex(const char *ifname) {
  struct ifreq ifr;
  int fd, rc;
  if (!ifname) { errno = EINVAL; return 0; }
  /* strncpy into a fixed field: the name must be NUL-padded and a name that
     does not fit is ENAMETOOLONG, not a silent truncation to a DIFFERENT
     interface that happens to share the first 15 characters. */
  if (strlen(ifname) >= IFNAMSIZ) { errno = ENAMETOOLONG; return 0; }
  memset(&ifr, 0, sizeof ifr);
  strncpy(ifr.ifr_name, ifname, IFNAMSIZ - 1);
  fd = if_sock();
  if (fd < 0) return 0;
  rc = ioctl(fd, SIOCGIFINDEX, &ifr);
  { int saved = errno; close(fd); errno = saved; }
  if (rc < 0) return 0;
  return (unsigned int)ifr.ifr_ifindex;
}

char *if_indextoname(unsigned int ifindex, char *ifname) {
  struct ifreq ifr;
  int fd, rc;
  if (!ifname) { errno = EINVAL; return 0; }
  memset(&ifr, 0, sizeof ifr);
  ifr.ifr_ifindex = (int)ifindex;
  fd = if_sock();
  if (fd < 0) return 0;
  rc = ioctl(fd, SIOCGIFNAME, &ifr);
  { int saved = errno; close(fd); errno = saved; }
  if (rc < 0) return 0;
  memcpy(ifname, ifr.ifr_name, IF_NAMESIZE);
  ifname[IF_NAMESIZE - 1] = '\0';
  return ifname;
}

/* The array and every name it points at are ONE allocation, so free() on the
   array frees the names too -- which is what if_freenameindex is allowed to
   assume and what callers who free it themselves get away with. */
struct if_nameindex *if_nameindex(void) {
  FILE *f;
  char line[512];
  char names[64][IF_NAMESIZE];
  int n = 0, i;
  struct if_nameindex *out;
  char *strp;
  unsigned long need;

  f = fopen("/proc/net/dev", "r");
  if (!f) return 0;
  /* Two header lines, then "  name: counters..." per device. */
  if (!fgets(line, (int)sizeof line, f) || !fgets(line, (int)sizeof line, f)) {
    fclose(f);
    errno = ENODEV;
    return 0;
  }
  while (n < 64 && fgets(line, (int)sizeof line, f)) {
    char *p = line, *colon;
    while (*p == ' ' || *p == '\t') p++;
    colon = strchr(p, ':');
    if (!colon) continue;
    *colon = '\0';
    if (colon - p >= IFNAMSIZ) continue;      /* not a name this ABI can hold */
    strcpy(names[n], p);
    n++;
  }
  fclose(f);

  need = (unsigned long)(n + 1) * sizeof(struct if_nameindex)
       + (unsigned long)n * IF_NAMESIZE;
  out = (struct if_nameindex *)malloc(need);
  if (!out) { errno = ENOMEM; return 0; }
  strp = (char *)(out + (n + 1));
  for (i = 0; i < n; i++) {
    memset(strp, 0, IF_NAMESIZE);
    strcpy(strp, names[i]);
    out[i].if_name = strp;
    out[i].if_index = if_nametoindex(names[i]);
    strp += IF_NAMESIZE;
  }
  /* The terminator is index 0 AND name NULL -- callers test either one. */
  out[n].if_index = 0;
  out[n].if_name = 0;
  return out;
}

void if_freenameindex(struct if_nameindex *ptr) {
  free(ptr);
}
