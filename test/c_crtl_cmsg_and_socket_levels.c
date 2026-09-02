/* crtl: ancillary-data walking (struct cmsghdr, CMSG_*) and the setsockopt
 * levels / address families.
 *
 * busybox's udhcp client needs both: it reads PACKET_AUXDATA off a recvmsg
 * control buffer and opens an AF_PACKET socket.
 *
 * THE CONSTANT ROWS ARE NOT TAUTOLOGIES. They are diffed against glibc's own
 * headers, which is the only thing that catches a transcribed digit -- and a
 * wrong one here does not fail: SOL_PACKET mistyped is a real level, and a
 * MISSING one is worse still, because pxx turns an undeclared identifier into
 * 0 with a warning and 0 is SOL_IP. Measured 2026-09-02: dhcpc.c compiled with
 * SOL_PACKET, AF_PACKET and PF_PACKET all silently 0.
 *
 * The walk rows build the control buffer by hand rather than calling recvmsg,
 * so the test needs no privileges and no network, and still exercises the
 * bounds CMSG_NXTHDR enforces -- including the one it deliberately does NOT.
 */
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <netinet/in.h>
#ifndef PACKET_AUXDATA
/* glibc has no PACKET_* of its own -- they live in the kernel's UAPI header.
   crtl carries the three it needs in <sys/socket.h>, so this include is for
   the gcc oracle only, and guarding it keeps a HOST kernel header out of every
   cross build of this file. */
#include <linux/if_packet.h>
#endif
/* glibc puts SOL_IP in netinet/in.h; crtl also has it in <sys/socket.h>,
                             which is us accepting more, not a divergence a
                             program can trip over */

int main(void)
{
  char buf[256];
  struct msghdr mh;
  struct cmsghdr *c;
  int n;
  int v;

  printf("1 %d %d %d %d\n", AF_UNSPEC, AF_INET, AF_PACKET, AF_NETLINK);
  printf("2 %d %d %d\n", PF_PACKET, PF_NETLINK, PF_INET);
  printf("3 %d %d %d %d\n", SOL_SOCKET, SOL_IP, SOL_PACKET, SOL_NETLINK);
  printf("4 %d\n", SOL_RAW);
  printf("5 %d %d\n", PACKET_AUXDATA, PACKET_ADD_MEMBERSHIP);

  /* Layout, against glibc's. cmsg_len is size_t and not socklen_t: the kernel
     writes the field, so the wrong width reads the length out of the top half
     of a 64-bit word. */
  printf("6 %d %d %d\n", (int)sizeof(struct cmsghdr),
         (int)(CMSG_DATA((struct cmsghdr *)buf) - (unsigned char *)buf),
         (int)CMSG_ALIGN(1));

  /* LEN vs SPACE: they differ only in whether the PAYLOAD is aligned, and
     swapping them compiles, runs, and truncates the last message. */
  printf("7 %d %d %d %d\n", (int)CMSG_LEN(0), (int)CMSG_SPACE(0),
         (int)CMSG_LEN(1), (int)CMSG_SPACE(1));

  /* Two messages, built by hand, then walked. */
  memset(buf, 0, sizeof buf);
  memset(&mh, 0, sizeof mh);
  mh.msg_control = buf;
  mh.msg_controllen = CMSG_SPACE(sizeof(int)) + CMSG_SPACE(sizeof(int));

  c = CMSG_FIRSTHDR(&mh);
  c->cmsg_level = SOL_SOCKET;
  c->cmsg_type = 1;
  c->cmsg_len = CMSG_LEN(sizeof(int));
  v = 111; memcpy(CMSG_DATA(c), &v, sizeof v);

  c = CMSG_NXTHDR(&mh, c);
  c->cmsg_level = SOL_PACKET;
  c->cmsg_type = PACKET_AUXDATA;
  c->cmsg_len = CMSG_LEN(sizeof(int));
  v = 222; memcpy(CMSG_DATA(c), &v, sizeof v);

  n = 0;
  for (c = CMSG_FIRSTHDR(&mh); c != 0; c = CMSG_NXTHDR(&mh, c)) {
    memcpy(&v, CMSG_DATA(c), sizeof v);
    printf("8 %d %d %d\n", c->cmsg_level, c->cmsg_type, v);
    n++;
  }
  printf("9 %d\n", n);

  /* An EMPTY control buffer must give no first header -- the bound that stops
     a walker from reading a header out of a zero-length buffer. */
  mh.msg_controllen = 0;
  printf("10 %d\n", CMSG_FIRSTHDR(&mh) == 0);

  /* A buffer that holds the first message and a bare header after it, but not
     the second message's payload. glibc returns that header, and this row
     pins that: CMSG_NXTHDR validates the CURRENT message's extent and does not
     read the next one's cmsg_len, which it has not vetted yet -- that happens
     on the following call, when the header is the current one. A stricter
     walker that also required the next payload to fit returns NULL here, and
     was written first; it was replaced because divergence in the direction of
     caution is still divergence, on a walk over kernel-supplied bytes where
     every other program on the system uses glibc's answer. */
  mh.msg_controllen = CMSG_SPACE(sizeof(int)) + sizeof(struct cmsghdr);
  c = CMSG_FIRSTHDR(&mh);
  printf("11 %d %d\n", c != 0, CMSG_NXTHDR(&mh, c) == 0);
  return 0;
}
