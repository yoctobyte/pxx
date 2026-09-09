/* SPDX-License-Identifier: Zlib */
/* Every constant crtl's headers claim, printed and compared against GCC'S VIEW
   OF THE SAME SOURCE. The Makefile compiles this file twice -- once with pxx
   against lib/crtl/include, once with gcc against the host's headers -- and
   diffs the two outputs, so there is no expected value written down anywhere
   and nothing to go stale.

   WHY IT EXISTS. These are values that TRAVEL: to the kernel in a setsockopt
   or an open(), and onto the wire in an ethernet type field. A wrong one does
   not fail to compile and does not raise an error at run time -- it asks for a
   different thing. And until 2026-09-04 the failure mode was worse than a
   wrong value: an absent one became ZERO, because pxx's C frontend accepts an
   undeclared identifier used as a value and only warns
   (bug-c-an-undeclared-identifier-used-as-a-value-is-a-warning-not-an-error).
   Eighteen constants across eleven busybox translation units were 0 in a build
   that passed 621 differential cases -- ETH_P_IP in the DHCP client's raw
   socket, IPDEFTTL in the header it writes, ICMP_TIMXCEED in traceroute's
   classifier, O_NOFOLLOW in unzip's and chattr's symlink guard, LONG_BIT as a
   shift distance in the TLS GHASH.

   THE POSITIVE CONTROL IS FREE AND MUST BE RUN BY HAND WHEN THIS FILE CHANGES:
   change one digit of one constant in the crtl header and this row differs.
   That case is real because the two sides are compiled from different header
   trees -- a self-comparison could not fail.

   ONE ROW IS DELIBERATELY NOT DIFFED. O_LARGEFILE is 0 in glibc on a 64-bit
   userspace (its off_t is already 64-bit, so the flag is redundant) and is the
   kernel's 0100000 everywhere. crtl takes the KERNEL's, because crtl's callers
   reach the kernel through <sys/syscall.h> rather than through glibc's open().
   Diffing it would report a divergence that is correct in both directions, so
   it is asserted here as a RELATION instead -- nonzero -- which is the part
   that is actually our choice and which a 0 would break. */

#define _GNU_SOURCE 1
#include <stdio.h>
#include <fcntl.h>
#include <termios.h>
#include <limits.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/ip.h>
#include <netinet/ip_icmp.h>
#include <linux/if_ether.h>
#include <net/if_arp.h>
#include <sys/ioctl.h>
#include <sys/mount.h>
#include <time.h>

#define P(x) printf("%-30s %ld\n", #x, (long)(x))

int main(void)
{
  /* open() flags -- <fcntl.h> */
  P(O_RDONLY);
  P(O_WRONLY);
  P(O_RDWR);
  P(O_ACCMODE);
  P(O_CREAT);
  P(O_EXCL);
  P(O_NOCTTY);
  P(O_TRUNC);
  P(O_APPEND);
  P(O_NONBLOCK);
  P(O_SYNC);
  P(O_DSYNC);
  P(O_CLOEXEC);
  P(O_ASYNC);
  P(O_NOATIME);
  P(O_PATH);
  P(O_NDELAY);
  P(O_FSYNC);
  P(O_RSYNC);
  P(O_DIRECTORY);
  P(O_NOFOLLOW);
  P(O_DIRECT);
  P(O_TMPFILE);

  /* c_oflag delays -- <termios.h> */
  P(NLDLY);
  P(NL0);
  P(NL1);
  P(CRDLY);
  P(CR0);
  P(CR1);
  P(CR2);
  P(CR3);
  P(TABDLY);
  P(TAB0);
  P(TAB1);
  P(TAB2);
  P(TAB3);
  P(XTABS);
  P(BSDLY);
  P(BS0);
  P(BS1);
  P(VTDLY);
  P(VT0);
  P(VT1);
  P(FFDLY);
  P(FF0);
  P(FF1);

  /* word sizes -- <limits.h> */
  P(LONG_BIT);
  P(WORD_BIT);

  /* socket types -- <sys/socket.h> */
  P(SOCK_PACKET);
  P(SOCK_NONBLOCK);
  P(SOCK_CLOEXEC);

  /* IPPROTO_IP options -- <netinet/in.h> */
  P(IP_TOS);
  P(IP_TTL);
  P(IP_HDRINCL);
  P(IP_OPTIONS);
  P(IP_ROUTER_ALERT);
  P(IP_RECVOPTS);
  P(IP_RETOPTS);
  P(IP_PKTINFO);
  P(IP_PKTOPTIONS);
  P(IP_MTU_DISCOVER);
  P(IP_RECVERR);
  P(IP_RECVTTL);
  P(IP_RECVTOS);
  P(IP_MTU);
  P(IP_FREEBIND);
  P(IP_IPSEC_POLICY);
  P(IP_XFRM_POLICY);
  P(IP_PASSSEC);
  P(IP_TRANSPARENT);
  P(IP_ORIGDSTADDR);
  P(IP_MINTTL);
  P(IP_NODEFRAG);
  P(IP_CHECKSUM);
  P(IP_BIND_ADDRESS_NO_PORT);
  P(IP_RECVFRAGSIZE);
  P(IP_RECVERR_RFC4884);
  P(IP_MULTICAST_IF);
  P(IP_MULTICAST_TTL);
  P(IP_MULTICAST_LOOP);
  P(IP_ADD_MEMBERSHIP);
  P(IP_DROP_MEMBERSHIP);
  P(IP_UNBLOCK_SOURCE);
  P(IP_BLOCK_SOURCE);
  P(IP_ADD_SOURCE_MEMBERSHIP);
  P(IP_DROP_SOURCE_MEMBERSHIP);
  P(IP_MSFILTER);
  P(IP_MULTICAST_ALL);
  P(IP_UNICAST_IF);
  P(IP_LOCAL_PORT_RANGE);
  P(IP_PROTOCOL);
  P(IP_PMTUDISC_DONT);
  P(IP_PMTUDISC_WANT);
  P(IP_PMTUDISC_DO);
  P(IP_PMTUDISC_PROBE);
  P(IP_PMTUDISC_INTERFACE);
  P(IP_PMTUDISC_OMIT);
  P(IP_DEFAULT_MULTICAST_LOOP);
  P(IP_DEFAULT_MULTICAST_TTL);

  /* IP header -- <netinet/ip.h> */
  P(IPVERSION);
  P(IPDEFTTL);
  P(IPFRAGTTL);
  P(IPTTLDEC);
  P(MAXTTL);
  P(IP_MSS);

  /* BSD ICMP names -- <netinet/ip_icmp.h> */
  P(ICMP_MINLEN);
  P(ICMP_MASKLEN);
  P(ICMP_ADVLENMIN);
  P(ICMP_ECHOREPLY);
  P(ICMP_DEST_UNREACH);
  P(ICMP_SOURCE_QUENCH);
  P(ICMP_REDIRECT);
  P(ICMP_ECHO);
  P(ICMP_ROUTERADVERT);
  P(ICMP_ROUTERSOLICIT);
  P(ICMP_TIME_EXCEEDED);
  P(ICMP_PARAMETERPROB);
  P(ICMP_TIMESTAMP);
  P(ICMP_TIMESTAMPREPLY);
  P(ICMP_INFO_REQUEST);
  P(ICMP_INFO_REPLY);
  P(ICMP_ADDRESS);
  P(ICMP_ADDRESSREPLY);
  P(ICMP_NET_UNREACH);
  P(ICMP_HOST_UNREACH);
  P(ICMP_PROT_UNREACH);
  P(ICMP_PORT_UNREACH);
  P(ICMP_FRAG_NEEDED);
  P(ICMP_SR_FAILED);
  P(ICMP_NET_UNKNOWN);
  P(ICMP_HOST_UNKNOWN);
  P(ICMP_HOST_ISOLATED);
  P(ICMP_NET_ANO);
  P(ICMP_HOST_ANO);
  P(ICMP_NET_UNR_TOS);
  P(ICMP_HOST_UNR_TOS);
  P(ICMP_PKT_FILTERED);
  P(ICMP_PREC_VIOLATION);
  P(ICMP_PREC_CUTOFF);
  P(ICMP_REDIR_NET);
  P(ICMP_REDIR_HOST);
  P(ICMP_REDIR_NETTOS);
  P(ICMP_REDIR_HOSTTOS);
  P(ICMP_EXC_TTL);
  P(ICMP_EXC_FRAGTIME);
  P(ICMP_UNREACH);
  P(ICMP_SOURCEQUENCH);
  P(ICMP_TIMXCEED);
  P(ICMP_PARAMPROB);
  P(ICMP_TSTAMP);
  P(ICMP_TSTAMPREPLY);
  P(ICMP_IREQ);
  P(ICMP_IREQREPLY);
  P(ICMP_MASKREQ);
  P(ICMP_MASKREPLY);
  P(ICMP_MAXTYPE);
  P(ICMP_UNREACH_NET);
  P(ICMP_UNREACH_HOST);
  P(ICMP_UNREACH_PROTOCOL);
  P(ICMP_UNREACH_PORT);
  P(ICMP_UNREACH_NEEDFRAG);
  P(ICMP_UNREACH_SRCFAIL);
  P(ICMP_UNREACH_NET_UNKNOWN);
  P(ICMP_UNREACH_HOST_UNKNOWN);
  P(ICMP_UNREACH_ISOLATED);
  P(ICMP_UNREACH_NET_PROHIB);
  P(ICMP_UNREACH_HOST_PROHIB);
  P(ICMP_UNREACH_TOSNET);
  P(ICMP_UNREACH_TOSHOST);
  P(ICMP_UNREACH_FILTER_PROHIB);
  P(ICMP_UNREACH_HOST_PRECEDENCE);
  P(ICMP_UNREACH_PRECEDENCE_CUTOFF);
  P(ICMP_REDIRECT_NET);
  P(ICMP_REDIRECT_HOST);
  P(ICMP_REDIRECT_TOSNET);
  P(ICMP_REDIRECT_TOSHOST);
  P(ICMP_TIMXCEED_INTRANS);
  P(ICMP_TIMXCEED_REASS);
  P(ICMP_PARAMPROB_OPTABSENT);

  /* ethernet -- <linux/if_ether.h> */
  P(ETH_ALEN);
  P(ETH_TLEN);
  P(ETH_HLEN);
  P(ETH_ZLEN);
  P(ETH_DATA_LEN);
  P(ETH_FRAME_LEN);
  P(ETH_FCS_LEN);
  P(ETH_MIN_MTU);
  P(ETH_MAX_MTU);
  P(ETH_P_LOOP);
  P(ETH_P_PUP);
  P(ETH_P_PUPAT);
  P(ETH_P_IP);
  P(ETH_P_X25);
  P(ETH_P_ARP);
  P(ETH_P_BPQ);
  P(ETH_P_IEEEPUP);
  P(ETH_P_IEEEPUPAT);
  P(ETH_P_DEC);
  P(ETH_P_RARP);
  P(ETH_P_ATALK);
  P(ETH_P_AARP);
  P(ETH_P_8021Q);
  P(ETH_P_IPX);
  P(ETH_P_IPV6);
  P(ETH_P_PAUSE);
  P(ETH_P_SLOW);
  P(ETH_P_WCCP);
  P(ETH_P_PPP_DISC);
  P(ETH_P_PPP_SES);
  P(ETH_P_MPLS_UC);
  P(ETH_P_MPLS_MC);
  P(ETH_P_ATMFATE);
  P(ETH_P_AOE);
  P(ETH_P_8021AD);
  P(ETH_P_TIPC);
  P(ETH_P_LLDP);
  P(ETH_P_FCOE);
  P(ETH_P_FIP);
  P(ETH_P_EDSA);
  P(ETH_P_802_3);
  P(ETH_P_AX25);
  P(ETH_P_ALL);
  P(ETH_P_802_2);
  P(ETH_P_SNAP);
  P(ETH_P_DDCMP);
  P(ETH_P_WAN_PPP);
  P(ETH_P_PPP_MP);
  P(ETH_P_LOCALTALK);
  P(ETH_P_CAN);
  P(ETH_P_CANFD);
  P(ETH_P_PPPTALK);
  P(ETH_P_TR_802_2);
  P(ETH_P_MOBITEX);
  P(ETH_P_CONTROL);
  P(ETH_P_IRDA);
  P(ETH_P_ECONET);
  P(ETH_P_HDLC);
  P(ETH_P_ARCNET);
  P(ETH_P_DSA);
  P(ETH_P_TRAILER);
  P(ETH_P_PHONET);
  P(ETH_P_IEEE802154);
  P(ETH_P_CAIF);
  P(ETH_P_XDSA);

  /* ARP -- <net/if_arp.h> */
  P(ARPHRD_ETHER);
  P(ARPHRD_FDDI);
  P(ARPOP_REQUEST);
  P(ARPOP_REPLY);

  /* The classful ADDRESS PARTS -- <netinet/in.h>. The IN_CLASSA..D predicates
     were here and these were not, which is a distinction with no visible edge:
     both spellings live in the same header and a program that has one expects
     the other. busybox networking/zcip.c picks its link-local host part with
     `rand() & IN_CLASSB_HOST', so the absent one was a 0 mask -- one constant
     address, forever, in a build that was recorded GREEN. */
  P(IN_CLASSA_NET);
  P(IN_CLASSA_NSHIFT);
  P(IN_CLASSA_HOST);
  P(IN_CLASSA_MAX);
  P(IN_CLASSB_NET);
  P(IN_CLASSB_NSHIFT);
  P(IN_CLASSB_HOST);
  P(IN_CLASSB_MAX);
  P(IN_CLASSC_NET);
  P(IN_CLASSC_NSHIFT);
  P(IN_CLASSC_HOST);
  P(IN_LOOPBACKNET);

  /* clockid_t -- <time.h>. Two of eleven were defined. CLOCK_BOOTTIME absent
     is CLOCK_REALTIME asked for instead, and busybox miscutils/seedrng.c hashes
     REALTIME and BOOTTIME together to seed the pool: with the second one 0 it
     hashed the same clock twice and the entropy it thought it was mixing in
     was not there. 10 is skipped by the kernel and by glibc; the gap is real. */
  P(CLOCK_REALTIME);
  P(CLOCK_MONOTONIC);
  P(CLOCK_PROCESS_CPUTIME_ID);
  P(CLOCK_THREAD_CPUTIME_ID);
  P(CLOCK_MONOTONIC_RAW);
  P(CLOCK_REALTIME_COARSE);
  P(CLOCK_MONOTONIC_COARSE);
  P(CLOCK_BOOTTIME);
  P(CLOCK_REALTIME_ALARM);
  P(CLOCK_BOOTTIME_ALARM);
  P(CLOCK_TAI);

  /* The block-device ioctls a program reaches through <sys/mount.h>. Every one
     of these was already correct in <linux/fs.h>; five of fifteen were reachable
     from the header glibc puts them in and that programs therefore include.
     busybox miscutils/hdparm.c includes <linux/hdreg.h> and <sys/mount.h> and
     asks for BLKRASET -- a NUMBER PRESENT IN THE TREE and absent from the
     caller's view, which greps as fixed and compiles as missing. */
  P(BLKROSET);
  P(BLKROGET);
  P(BLKRRPART);
  P(BLKGETSIZE);
  P(BLKFLSBUF);
  P(BLKRASET);
  P(BLKRAGET);
  P(BLKFRASET);
  P(BLKFRAGET);
  P(BLKSECTSET);
  P(BLKSECTGET);
  P(BLKSSZGET);
  P(BLKBSZGET);
  P(BLKBSZSET);
  P(BLKGETSIZE64);

  /* THESE THREE ARE HERE BECAUSE OF A COMMENT, not because of a missing number.
     crtl's <sys/mount.h> transcribed glibc's joke about MS_VERBOSE -- "War is
     peace. Verbosity is silence." -- and dropped the second line it ends on, so
     the comment ran unterminated through MS_SILENT and closed on MS_POSIXACL's
     own trailing comment. Two mount flags were eaten by a pun. The compiler
     said `warning: slash-star within comment' the whole time and nothing read
     it -- and spelling that warning literally here would reproduce it. */
  P(MS_VERBOSE);
  P(MS_SILENT);
  P(MS_POSIXACL);

  /* Line disciplines -- <sys/ioctl.h> via bits/ioctl-types.h. TIOCSETD was
     here and the numbers it takes were not. busybox networking/slattach.c
     hands ioctl(fd, TIOCSETD, &N_SLIP) to make a serial line carry SLIP; with
     N_SLIP absent that is discipline 0, N_TTY, which is an ordinary terminal
     and reports success. */
  P(N_TTY);
  P(N_SLIP);
  P(N_MOUSE);
  P(N_PPP);
  P(N_STRIP);
  P(N_AX25);
  P(N_X25);
  P(N_6PACK);
  P(N_MASC);
  P(N_R3964);
  P(N_PROFIBUS_FDL);
  P(N_IRDA);
  P(N_SMSBLOCK);
  P(N_HDLC);
  P(N_SYNC_PPP);

  /* Modem status bits -- same header. TIOCMGET/TIOCMSET/TIOCMBIC/TIOCMBIS were
     in crtl and the bits they carry were not, which is the line-discipline
     shape again. slattach polls carrier with `modem & TIOCM_CAR'; at 0 that is
     carrier permanently absent. FOUND ON THE SECOND PASS, after N_SLIP was
     fixed -- a first-error-per-TU census names the first wall in a file and
     never the ones behind it. */
  P(TIOCM_LE);
  P(TIOCM_DTR);
  P(TIOCM_RTS);
  P(TIOCM_ST);
  P(TIOCM_SR);
  P(TIOCM_CTS);
  P(TIOCM_CAR);
  P(TIOCM_RNG);
  P(TIOCM_DSR);
  P(TIOCM_CD);
  P(TIOCM_RI);

  /* Not diffed -- see the note at the top. */
  printf("%-30s %d\n", "O_LARGEFILE_NONZERO", O_LARGEFILE != 0);
  return 0;
}
