/* crtl: <arpa/telnet.h>, <sys/prctl.h>, <netpacket/packet.h>,
 * <linux/types.h>, <asm/types.h>, <sys/vfs.h>, <features.h>.
 *
 * Every one found by attempting busybox for i386, where there is no host
 * /usr/include to fall back on.
 *
 * A WRONG PROTOCOL CONSTANT DOES NOT FAIL TO COMPILE -- it puts a different
 * byte on the wire. The telnet command bytes run DOWNWARD from IAC=255, which
 * is exactly the shape a transposition survives: SB and SE differ by ten and
 * both are plausible, and the two ends then disagree about where a
 * subnegotiation ended. So rows 1-4 are diffed against the host's own
 * <arpa/telnet.h> rather than asserted from the RFC.
 *
 * Row 6 is struct sockaddr_ll's LAYOUT, not just its size: sll_addr is EIGHT
 * bytes -- the kernel's maximum hardware address, not ethernet's six -- and a
 * six-byte version has every preceding field at the right offset and the wrong
 * sizeof, which is what `bind(fd, &sa, sizeof sa)' hands the kernel.
 *
 * ROW 8 IS THE ONE ROW HERE THAT IS NOT AN ORACLE COMPARISON, and it is
 * inverted on purpose: gcc prints `glibc' and pxx must print `not-glibc'.
 * <features.h> exists in crtl for no other reason than to make __GLIBC__ stay
 * undefined -- busybox's libbb/makedev.c includes it and then takes glibc's
 * arm under `#ifdef __GLIBC__', wrapping an inline that is not there. A crtl
 * with no <features.h> reaches the HOST's, which answers correctly about the
 * wrong libc; that is the failure this row is aimed at, and agreeing with gcc
 * would mean it had happened.
 *
 * The rest ARE diffed against gcc, and row 4 has already earned it: this file
 * was first written without TELOPT_TSPEED, which shifted LFLOW, LINEMODE and
 * XDISPLOC each down by one and compiled perfectly.
 */
#include <stdio.h>
#include <stddef.h>
#include <arpa/telnet.h>
#include <sys/prctl.h>
#include <netpacket/packet.h>
#include <linux/types.h>
#include <sys/vfs.h>
#include <features.h>
#include <string.h>
#include <errno.h>

int main(void)
{
  char nm[24];
  int rc;

  printf("1 %d %d %d %d %d %d\n", IAC, DONT, DO, WONT, WILL, SB);
  printf("2 %d %d %d %d %d\n", SE, NOP, DM, AYT, GA);
  printf("3 %d %d %d %d %d\n", TELOPT_BINARY, TELOPT_ECHO, TELOPT_SGA,
         TELOPT_TTYPE, TELOPT_NAWS);
  printf("4 %d %d %d %d\n", TELOPT_LFLOW, TELQUAL_IS, TELQUAL_SEND, TELQUAL_INFO);

  printf("5 %d %d %d %d %d %d\n", PR_SET_NAME, PR_GET_NAME, PR_CAPBSET_READ,
         PR_SET_NO_NEW_PRIVS, PR_GET_NO_NEW_PRIVS, PR_CAP_AMBIENT);

  printf("6 %d | %d %d %d %d %d %d %d\n", (int)sizeof(struct sockaddr_ll),
         (int)offsetof(struct sockaddr_ll, sll_family),
         (int)offsetof(struct sockaddr_ll, sll_protocol),
         (int)offsetof(struct sockaddr_ll, sll_ifindex),
         (int)offsetof(struct sockaddr_ll, sll_hatype),
         (int)offsetof(struct sockaddr_ll, sll_pkttype),
         (int)offsetof(struct sockaddr_ll, sll_halen),
         (int)offsetof(struct sockaddr_ll, sll_addr));

  printf("7 %d %d %d %d %d\n", (int)sizeof(__u8), (int)sizeof(__u16),
         (int)sizeof(__u32), (int)sizeof(__u64), (int)sizeof(__le32));

#ifdef __GLIBC__
  printf("8 glibc\n");
#else
  printf("8 not-glibc\n");
#endif

  /* prctl actually issued: set the name, then read it back. */
  memset(nm, 0, sizeof nm);
  rc = prctl(PR_SET_NAME, (unsigned long)(size_t)"pxxprobe", 0, 0, 0);
  if (rc == 0) rc = prctl(PR_GET_NAME, (unsigned long)(size_t)nm, 0, 0, 0);
  printf("9 %d %s\n", rc, rc == 0 ? nm : "(failed)");
  return 0;
}
