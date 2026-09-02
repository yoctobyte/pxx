/* crtl: <linux/rtnetlink.h> and the four headers it drags in --
 * <linux/if_link.h>, <linux/if_addr.h>, <linux/neighbour.h> -- plus
 * <linux/fib_rules.h>. Found attempting busybox for i386: networking/ip.c,
 * libiproute/ip_parse_common_args.c, libiproute/utils.c.
 *
 * ROWS 3 AND 4 ARE THE POINT. Every rtnetlink reply is walked with
 * RTA_OK/RTA_NEXT/RTA_DATA over RTA_ALIGNTO=4, so the macros ARE the
 * interface, and an RTA_LENGTH that forgot the align does not fail to compile
 * -- it walks a real message off by a few bytes and reads a plausible wrong
 * attribute out of it. RTA_LENGTH(5) is 9 and not 8: the align applies to the
 * HEADER, not to the payload, and getting that backwards is the mistake that
 * looks right. Row 4 builds a real rtattr and evaluates the whole walk.
 *
 * ROW 2 IS THE RTM_* ARITHMETIC. The message types come in threes --
 * NEW/DEL/GET consecutive, each family starting on a multiple of four -- and
 * RTM_FAM(cmd) recovers the family by dividing. A type inserted out of order
 * breaks that silently.
 *
 * ROW 8 IS IFA_ADDRESS AGAINST IFA_LOCAL, which are 1 and 2 and are NOT
 * interchangeable: on a point-to-point link IFA_LOCAL is this end and
 * IFA_ADDRESS is the PEER. On an ordinary broadcast interface the kernel sends
 * both with the same value, so reading the wrong one works everywhere until it
 * meets a tunnel and reports the far end as the machine's own address.
 *
 * ROW 13 IS WHY <linux/if_link.h> IS TRANSCRIBED WHOLE rather than to taste.
 * The IFLA_* spaces are NESTED and each is numbered from 1 independently:
 * IFLA_VLAN_EGRESS_QOS and IFLA_MACVLAN_MACADDR_MODE are BOTH 3,
 * IFLA_BR_HELLO_TIME is 2, and IFLA_MTU -- in the outer space -- is 4. Only
 * the enclosing IFLA_INFO_DATA says which space is in force, so a value
 * transcribed from the wrong one is a legal attribute id and the kernel
 * accepts it.
 *
 * ROW 11 is rtnl_link_stats against rtnl_link_stats64: the same fields at two
 * widths, sent under IFLA_STATS and IFLA_STATS64. Reading the 64-bit struct
 * out of the 32-bit attribute gives byte counts that look plausible.
 *
 * All rows diffed against gcc.
 */
#include <stdio.h>
#include <stddef.h>
#include <string.h>
#include <linux/rtnetlink.h>
#include <linux/fib_rules.h>

int main(void)
{
  char buf[256];
  struct rtattr *r;
  int n;

  printf("1 %d %d %d %d %d\n", (int)sizeof(struct rtmsg), (int)sizeof(struct rtattr),
         (int)sizeof(struct ifinfomsg), (int)sizeof(struct ifaddrmsg),
         (int)sizeof(struct ndmsg));
  printf("2 %d %d %d | %d %d %d\n", RTM_NEWROUTE, RTM_DELROUTE, RTM_GETROUTE,
         RTM_NEWLINK, RTM_NEWADDR, RTM_NEWNEIGH);
  printf("3 %d %d %d\n", RTA_ALIGNTO, (int)RTA_LENGTH(0), (int)RTA_LENGTH(5));

  memset(buf, 0, sizeof buf);
  r = (struct rtattr *)buf;
  r->rta_type = RTA_DST;
  r->rta_len = RTA_LENGTH(4);
  n = RTA_LENGTH(4);
  printf("4 %d %d %d %d\n", (int)RTA_OK(r, n), (int)r->rta_len,
         (int)((char *)RTA_DATA(r) - (char *)r), (int)RTA_PAYLOAD(r));

  printf("5 %d %d %d %d %d\n", RTA_DST, RTA_SRC, RTA_OIF, RTA_GATEWAY, RTA_TABLE);
  printf("6 %d %d %d %d\n", RT_TABLE_MAIN, RT_TABLE_LOCAL, RT_SCOPE_UNIVERSE,
         RT_SCOPE_LINK);
  printf("7 %d %d %d %d\n", RTN_UNICAST, RTN_LOCAL, RTPROT_KERNEL, RTPROT_STATIC);
  printf("8 %d %d %d | %d %d\n", IFA_ADDRESS, IFA_LOCAL, IFA_LABEL,
         IFA_F_SECONDARY, IFA_F_PERMANENT);
  printf("9 %d %d %d | %x %x %x\n", NDA_DST, NDA_LLADDR, NDA_CACHEINFO,
         NUD_REACHABLE, NUD_PERMANENT, NUD_NOARP);
  printf("10 %d %d %d %d\n", IFLA_IFNAME, IFLA_MTU, IFLA_STATS, IFLA_STATS64);
  printf("11 %d %d\n", (int)sizeof(struct rtnl_link_stats),
         (int)sizeof(struct rtnl_link_stats64));
  printf("12 %d %d | %d %d %d\n", (int)sizeof(struct fib_rule_hdr), FR_ACT_UNSPEC,
         FR_ACT_TO_TBL, FRA_DST, FRA_TABLE);
  printf("13 %d %d | %d %d %d\n", IFLA_INFO_KIND, IFLA_INFO_DATA,
         IFLA_BR_HELLO_TIME, IFLA_VLAN_EGRESS_QOS, IFLA_MACVLAN_MACADDR_MODE);
  return 0;
}
