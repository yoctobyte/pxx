/* bind, connect, accept, sendto, recvfrom, getsockname and getpeername with
   address families other than AF_INET: lib/crtl/src/netinet/in.c used to
   refuse every one of them with EINVAL before any system call (busybox ip's
   AF_NETLINK, udhcpc's AF_PACKET). Linux x86-64; the output is gcc's. */
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <netinet/in.h>
#include <linux/netlink.h>

static void unix_stream(void) {
  struct sockaddr_un a, got;
  socklen_t gl;
  char path[64], buf[16];
  int srv, cli, acc, rc;
  ssize_t n;
  snprintf(path, sizeof path, "/tmp/pxx_sockfam_%d", (int)getpid());
  unlink(path);
  memset(&a, 0, sizeof a);
  a.sun_family = AF_UNIX;
  strcpy(a.sun_path, path);
  srv = socket(AF_UNIX, SOCK_STREAM, 0);
  printf("unix bind %d\n", bind(srv, (struct sockaddr *)&a, sizeof a));
  printf("unix listen %d\n", listen(srv, 1));
  gl = sizeof got; memset(&got, 0, sizeof got);
  rc = getsockname(srv, (struct sockaddr *)&got, &gl);
  printf("unix getsockname %d family=%d same=%d\n", rc, got.sun_family,
         strcmp(got.sun_path, path) == 0);
  cli = socket(AF_UNIX, SOCK_STREAM, 0);
  printf("unix connect %d\n", connect(cli, (struct sockaddr *)&a, sizeof a));
  gl = sizeof got; memset(&got, 0xff, sizeof got);
  acc = accept(srv, (struct sockaddr *)&got, &gl);
  printf("unix accept %d family=%d\n", acc >= 0, got.sun_family);
  gl = sizeof got; memset(&got, 0, sizeof got);
  rc = getpeername(cli, (struct sockaddr *)&got, &gl);
  printf("unix getpeername %d same=%d\n", rc, strcmp(got.sun_path, path) == 0);
  printf("unix sendto-null %d\n", (int)sendto(cli, "hello", 5, 0, NULL, 0));
  n = recv(acc, buf, sizeof buf - 1, 0);
  buf[n > 0 ? n : 0] = 0;
  printf("unix recv %d %s\n", (int)n, buf);
  close(acc); close(cli); close(srv);
  unlink(path);
}

static void inet6_udp(void) {
  struct sockaddr_in6 a, from;
  socklen_t al = sizeof a, fl = sizeof from;
  char buf[16];
  int s, c, rc;
  ssize_t n;
  s = socket(AF_INET6, SOCK_DGRAM, 0);
  if (s < 0) { printf("inet6 none\n"); return; }
  memset(&a, 0, sizeof a);
  a.sin6_family = AF_INET6;
  a.sin6_addr = in6addr_loopback;
  printf("inet6 bind %d\n", bind(s, (struct sockaddr *)&a, sizeof a));
  rc = getsockname(s, (struct sockaddr *)&a, &al);
  printf("inet6 getsockname %d family=%d port>0=%d\n", rc, a.sin6_family, a.sin6_port != 0);
  c = socket(AF_INET6, SOCK_DGRAM, 0);
  printf("inet6 sendto %d\n", (int)sendto(c, "six", 3, 0, (struct sockaddr *)&a, sizeof a));
  memset(&from, 0, sizeof from);
  n = recvfrom(s, buf, sizeof buf - 1, 0, (struct sockaddr *)&from, &fl);
  buf[n > 0 ? n : 0] = 0;
  printf("inet6 recvfrom %d %s family=%d len=%d\n", (int)n, buf, from.sin6_family, (int)fl);
  close(c); close(s);
}

static void netlink(void) {
  struct sockaddr_nl nl;
  socklen_t l = sizeof nl;
  int rc, s = socket(AF_NETLINK, SOCK_RAW, NETLINK_ROUTE);
  if (s < 0) { printf("netlink none\n"); return; }
  memset(&nl, 0, sizeof nl);
  nl.nl_family = AF_NETLINK;
  printf("netlink bind %d\n", bind(s, (struct sockaddr *)&nl, sizeof nl));
  memset(&nl, 0, sizeof nl);
  rc = getsockname(s, (struct sockaddr *)&nl, &l);
  printf("netlink getsockname %d family=%d len=%d pid>0=%d\n", rc, nl.nl_family, (int)l,
         nl.nl_pid != 0);
  close(s);
}

int main(void) {
  unix_stream();
  inet6_udp();
  netlink();
  return 0;
}
