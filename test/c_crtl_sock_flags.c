/* SPDX-License-Identifier: Zlib */
/* send/recv/sendto/recvfrom FLAGS, diffed against glibc.
 *
 * THE FAILURE THIS IS WRITTEN FOR IS A HANG, AND THIS TEST CAN HANG. crtl's
 * four socket wrappers said `(void)flags;', so MSG_PEEK was dropped: the first
 * peek CONSUMED the bytes and a second one waited forever for data that had
 * already been read. Every peek row adds MSG_DONTWAIT so that a
 * PARTIALLY dropped flag word reports -1/EAGAIN instead of blocking -- but
 * when the flag word is dropped ENTIRELY, MSG_DONTWAIT goes with it and peek2
 * blocks. Measured, not assumed: the positive control (restoring `(void)flags'
 * in recv alone) exits 124 under `timeout 20', having printed peek1 and
 * nothing after it. THE MAKEFILE THEREFORE RUNS THIS UNDER `timeout'. A
 * regression here is a hung build otherwise, and a hung build is the one
 * failure that gets read as an infrastructure problem rather than as a test
 * saying something.
 *
 * ROW 2 IS THE ASSERTION AND ROW 1 IS NOT. A single peek returns 8 with the
 * right bytes whether or not the flag reached the kernel -- an ordinary recv
 * does exactly that. Only the SECOND peek can tell them apart, which is why
 * the ticket's repro needed two.
 *
 * EVERY EXPECTED VALUE COMES FROM GLIBC'S OWN RUN, not from a literal: EAGAIN
 * is 11 on Linux and EWOULDBLOCK is its synonym, but that is the kernel's
 * choice and not ours to assert. The Makefile diffs this binary's output
 * against the gcc-built one.
 *
 * NO sleep() AND NO FIXED PORT. Bind to 0 and read back what the kernel gave,
 * as test/lib_sockets.pas does -- a fixed port made two concurrent runs
 * collide once already. */

#define _GNU_SOURCE 1
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

static const char PAYLOAD[8] = "PEEKME01";

static void show(const char *label, long rc, const char *buf, int e)
{
  printf("%-14s rc=%-3ld", label, rc);
  if (rc == 8 && buf) printf(" bytes=%s", memcmp(buf, PAYLOAD, 8) == 0 ? "same" : "DIFF");
  else if (rc < 0)    printf(" errno=%d", e);
  printf("\n");
}

/* Peek with MSG_DONTWAIT, retrying while the bytes are still in flight.
   The retry is bounded and the bound is reported, so "never arrived" is a
   distinct outcome from "arrived and the flag was dropped". */
static long peek(int fd, char *buf, int *ep)
{
  int tries;
  long rc = -1;
  for (tries = 0; tries < 10000; tries++) {
    errno = 0;
    rc = recv(fd, buf, 8, MSG_PEEK | MSG_DONTWAIT);
    if (rc >= 0) break;
    if (errno != EAGAIN && errno != EWOULDBLOCK) break;
  }
  *ep = errno;
  return rc;
}

int main(void)
{
  int srv, cli, conn, ud1, ud2;
  struct sockaddr_in a;
  socklen_t alen;
  char b1[8], b2[8], b3[8];
  long rc;
  int e;

  srv = socket(AF_INET, SOCK_STREAM, 0);
  memset(&a, 0, sizeof a);
  a.sin_family = AF_INET;
  a.sin_port = htons(0);
  a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  if (bind(srv, (struct sockaddr *)&a, sizeof a) != 0) { printf("bind FAIL\n"); return 1; }
  if (listen(srv, 4) != 0) { printf("listen FAIL\n"); return 1; }
  alen = sizeof a;
  if (getsockname(srv, (struct sockaddr *)&a, &alen) != 0) { printf("sockname FAIL\n"); return 1; }

  cli = socket(AF_INET, SOCK_STREAM, 0);
  if (connect(cli, (struct sockaddr *)&a, sizeof a) != 0) { printf("connect FAIL\n"); return 1; }
  alen = sizeof a;
  conn = accept(srv, (struct sockaddr *)&a, &alen);
  if (conn < 0) { printf("accept FAIL\n"); return 1; }

  /* 1: MSG_NOSIGNAL on the send. Accepted everywhere; the PAL sets it anyway. */
  errno = 0;
  rc = send(conn, PAYLOAD, 8, MSG_NOSIGNAL);
  show("send-nosignal", rc, 0, errno);

  memset(b1, 0, 8); memset(b2, 0, 8); memset(b3, 0, 8);
  rc = peek(cli, b1, &e);
  show("peek1", rc, b1, e);
  rc = peek(cli, b2, &e);
  show("peek2", rc, b2, e);          /* THE ROW. -1/EAGAIN means peek consumed. */

  /* 4: a real read still finds the bytes a peek must have left behind. */
  errno = 0;
  rc = recv(cli, b3, 8, 0);
  show("recv-after", rc, b3, errno);

  /* 5: and the queue is now empty, which MSG_DONTWAIT reports rather than
     blocking. A dropped MSG_DONTWAIT hangs here instead of answering. */
  errno = 0;
  rc = recv(cli, b3, 8, MSG_DONTWAIT);
  show("recv-empty", rc, 0, errno);

  /* 6: MSG_WAITALL over a message that is already complete. Weak on its own --
     it cannot distinguish "waited" from "did not need to" -- and included
     because it is the one remaining carried flag, so a translation that
     mis-maps it is at least reachable. */
  send(conn, PAYLOAD, 8, 0);
  errno = 0;
  rc = recv(cli, b3, 8, MSG_WAITALL);
  show("recv-waitall", rc, b3, errno);

  close(conn); close(cli); close(srv);

  /* 7-8: the datagram pair. sendto/recvfrom carry flags through a different
     PAL entry than send/recv, and it was the same `(void)flags'. */
  ud1 = socket(AF_INET, SOCK_DGRAM, 0);
  ud2 = socket(AF_INET, SOCK_DGRAM, 0);
  memset(&a, 0, sizeof a);
  a.sin_family = AF_INET;
  a.sin_port = htons(0);
  a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  if (bind(ud2, (struct sockaddr *)&a, sizeof a) != 0) { printf("ubind FAIL\n"); return 1; }
  alen = sizeof a;
  if (getsockname(ud2, (struct sockaddr *)&a, &alen) != 0) { printf("usockname FAIL\n"); return 1; }
  sendto(ud1, PAYLOAD, 8, 0, (struct sockaddr *)&a, sizeof a);

  {
    struct sockaddr_in from;
    socklen_t fl;
    int tries;
    memset(b1, 0, 8); memset(b2, 0, 8);
    for (tries = 0; tries < 10000; tries++) {
      fl = sizeof from; errno = 0;
      rc = recvfrom(ud2, b1, 8, MSG_PEEK | MSG_DONTWAIT, (struct sockaddr *)&from, &fl);
      if (rc >= 0) break;
      if (errno != EAGAIN && errno != EWOULDBLOCK) break;
    }
    show("upeek1", rc, b1, errno);
    fl = sizeof from; errno = 0;
    rc = recvfrom(ud2, b2, 8, MSG_PEEK | MSG_DONTWAIT, (struct sockaddr *)&from, &fl);
    show("upeek2", rc, b2, errno);
    fl = sizeof from; errno = 0;
    rc = recvfrom(ud2, b2, 8, 0, (struct sockaddr *)&from, &fl);
    show("urecv-after", rc, b2, errno);
  }
  close(ud1); close(ud2);
  return 0;
}
