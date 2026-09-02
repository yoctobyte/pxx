/* crtl: <linux/netlink.h> -- the base netlink protocol.
 *
 * Found attempting busybox for i386, where there is no host UAPI tree to fall
 * back on: libbb/xconnect.c and util-linux/uevent.c stop at this include, and
 * networking/ip.c and libiproute need it plus rtnetlink on top.
 *
 * THE MACROS ARE THE POINT, NOT THE STRUCT. Every netlink walk is
 * NLMSG_OK/NLMSG_NEXT arithmetic over NLMSG_ALIGNTO=4, and an NLMSG_HDRLEN
 * that is sizeof-without-the-align rather than 16 does not fail to compile --
 * it walks the kernel's reply off by a few bytes and reads a plausible wrong
 * message out of a real one. So rows 4-8 EVALUATE the macros (including
 * NLMSG_NEXT's pointer walk and the length it decrements) instead of checking
 * that they exist, and every row is diffed against the host's own header.
 *
 * Row 9 is the flag block, which is where reading across from a table goes
 * wrong quietly: NLM_F_ROOT/MATCH/ATOMIC and NLM_F_REPLACE/EXCL/CREATE REUSE
 * the same three bits with different meanings, so a value copied from the
 * wrong half is still a legal flag.
 */
#include <stdio.h>
#include <string.h>
#include <stddef.h>
#include <linux/netlink.h>
int main(void){
  char buf[256];
  struct nlmsghdr *nlh = (struct nlmsghdr *)buf;
  int len;
  printf("1 %d %d\n", (int)sizeof(struct sockaddr_nl), (int)sizeof(struct nlmsghdr));
  printf("2 %d %d %d %d\n", (int)offsetof(struct sockaddr_nl, nl_family),
    (int)offsetof(struct sockaddr_nl, nl_pad), (int)offsetof(struct sockaddr_nl, nl_pid),
    (int)offsetof(struct sockaddr_nl, nl_groups));
  printf("3 %d %d %d %d %d\n", (int)offsetof(struct nlmsghdr, nlmsg_len),
    (int)offsetof(struct nlmsghdr, nlmsg_type), (int)offsetof(struct nlmsghdr, nlmsg_flags),
    (int)offsetof(struct nlmsghdr, nlmsg_seq), (int)offsetof(struct nlmsghdr, nlmsg_pid));
  printf("4 %d %d %d %d\n", (int)NLMSG_ALIGNTO, NLMSG_HDRLEN,
    (int)NLMSG_ALIGN(13), (int)NLMSG_ALIGN(16));
  printf("5 %d %d %d %d\n", (int)NLMSG_LENGTH(0), (int)NLMSG_LENGTH(13),
    (int)NLMSG_SPACE(0), (int)NLMSG_SPACE(13));
  memset(buf, 0, sizeof buf);
  nlh->nlmsg_len = NLMSG_LENGTH(20);
  printf("6 %d %d\n", (int)((char *)NLMSG_DATA(nlh) - buf), (int)NLMSG_PAYLOAD(nlh, 0));
  len = 64;
  printf("7 %d\n", NLMSG_OK(nlh, len) ? 1 : 0);
  nlh = NLMSG_NEXT(nlh, len);
  printf("8 %d %d\n", (int)((char *)nlh - buf), len);
  printf("9 %x %x %x %x %x %x\n", NLM_F_REQUEST, NLM_F_MULTI, NLM_F_ACK, NLM_F_DUMP,
    NLM_F_CREATE, NLM_F_APPEND);
  printf("10 %d %d %d %d %d\n", NLMSG_NOOP, NLMSG_ERROR, NLMSG_DONE, NLMSG_OVERRUN, NLMSG_MIN_TYPE);
  printf("11 %d %d %d %d\n", NETLINK_ROUTE, NETLINK_KOBJECT_UEVENT, NETLINK_GENERIC,
    (int)sizeof(struct nlmsgerr));
  return 0;
}
