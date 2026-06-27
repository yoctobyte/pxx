#include "socket.c"

int main(void) {
  int srv, cli, conn, udp_rx, udp_tx, one, got;
  socklen_t alen;
  struct sockaddr_in a, peer;
  char sbuf[6];
  char rbuf[8];
  int i;

  srv = socket(AF_INET, SOCK_STREAM, 0);
  if (srv < 0) return 1;
  one = 1;
  if (setsockopt(srv, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one)) != 0) return 2;

  a.sin_family = AF_INET;
  a.sin_port = htons(28745);
  a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  for (i = 0; i < 8; i++) a.sin_zero[i] = 0;

  if (bind(srv, (struct sockaddr *)&a, sizeof(a)) != 0) return 3;
  if (listen(srv, 4) != 0) return 4;

  cli = socket(AF_INET, SOCK_STREAM, 0);
  if (cli < 0) return 5;
  if (connect(cli, (struct sockaddr *)&a, sizeof(a)) != 0) return 6;

  alen = sizeof(a);
  conn = accept(srv, (struct sockaddr *)&a, &alen);
  if (conn < 0) return 7;

  for (i = 0; i < 6; i++) sbuf[i] = (char)('A' + i);
  if (send(cli, sbuf, 6, 0) != 6) return 8;
  got = (int)recv(conn, rbuf, sizeof(rbuf), 0);
  if (got != 6) return 9;
  for (i = 0; i < 6; i++) if (rbuf[i] != (char)('A' + i)) return 10;

  if (close(conn) != 0) return 11;
  if (close(cli) != 0) return 12;
  if (close(srv) != 0) return 13;

  udp_rx = socket(AF_INET, SOCK_DGRAM, 0);
  if (udp_rx < 0) return 14;
  a.sin_family = AF_INET;
  a.sin_port = htons(28746);
  a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  for (i = 0; i < 8; i++) a.sin_zero[i] = 0;
  if (bind(udp_rx, (struct sockaddr *)&a, sizeof(a)) != 0) return 15;

  alen = sizeof(peer);
  if (getsockname(udp_rx, (struct sockaddr *)&peer, &alen) != 0) return 16;
  if (peer.sin_port != htons(28746)) return 17;

  udp_tx = socket(AF_INET, SOCK_DGRAM, 0);
  if (udp_tx < 0) return 18;
  if (sendto(udp_tx, sbuf, 6, 0, (struct sockaddr *)&a, sizeof(a)) != 6) return 19;
  alen = sizeof(peer);
  got = (int)recvfrom(udp_rx, rbuf, sizeof(rbuf), 0, (struct sockaddr *)&peer, &alen);
  if (got != 6) return 20;
  for (i = 0; i < 6; i++) if (rbuf[i] != (char)('A' + i)) return 21;
  if (peer.sin_addr.s_addr != htonl(INADDR_LOOPBACK)) return 22;

  if (close(udp_tx) != 0) return 23;
  if (close(udp_rx) != 0) return 24;
  return 42;
}
