/* sendmsg/recvmsg on an UNCONNECTED UDP socket, the shape ENet uses for every
 * packet: a header iovec plus a payload iovec, and the peer address in
 * msg_name. crtl used to send each iovec as its own send() and ignore
 * msg_name, so the first fragment failed with EDESTADDRREQ and ENet's
 * loopback server and client never connected. One message must be ONE
 * datagram, and recvmsg must scatter it and report the sender.
 * Values are gcc's. */
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <sys/socket.h>
#include <sys/uio.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>

int main(void) {
  int rx = socket(AF_INET, SOCK_DGRAM, 0), tx = socket(AF_INET, SOCK_DGRAM, 0);
  struct sockaddr_in a, from, txa;
  socklen_t alen = sizeof a, txlen = sizeof txa;
  struct msghdr m;
  struct iovec v[2], w[3];
  char h[4] = "HDR", p[8] = "payload", r1[2], r2[5], r3[16];
  ssize_t n;
  memset(&a, 0, sizeof a);
  a.sin_family = AF_INET;
  a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  a.sin_port = 0;
  if (bind(rx, (struct sockaddr *)&a, sizeof a) < 0) { printf("bind rx failed\n"); return 1; }
  getsockname(rx, (struct sockaddr *)&a, &alen);
  bind(tx, (struct sockaddr *)&txa, 0 * txlen);  /* unbound: the send binds it */

  memset(&m, 0, sizeof m);
  v[0].iov_base = h; v[0].iov_len = 4;
  v[1].iov_base = p; v[1].iov_len = 8;
  m.msg_name = &a; m.msg_namelen = sizeof a;
  m.msg_iov = v; m.msg_iovlen = 2;
  n = sendmsg(tx, &m, 0);
  printf("sent %d\n", (int)n);
  getsockname(tx, (struct sockaddr *)&txa, &txlen);

  memset(&m, 0, sizeof m); memset(&from, 0, sizeof from);
  memset(r1, '.', sizeof r1); memset(r2, '.', sizeof r2); memset(r3, '.', sizeof r3);
  w[0].iov_base = r1; w[0].iov_len = 2;
  w[1].iov_base = r2; w[1].iov_len = 5;
  w[2].iov_base = r3; w[2].iov_len = 16;
  m.msg_name = &from; m.msg_namelen = sizeof from;
  m.msg_iov = w; m.msg_iovlen = 3;
  n = recvmsg(rx, &m, 0);
  printf("received %d namelen %d family-inet %d same-port %d loopback %d\n", (int)n,
         (int)m.msg_namelen, from.sin_family == AF_INET,
         from.sin_port == txa.sin_port, ntohl(from.sin_addr.s_addr) == INADDR_LOOPBACK);
  printf("r1 %.2s r2 %.5s r3 %.5s\n", r1, r2, r3);
  close(rx); close(tx);
  return 0;
}
