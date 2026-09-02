/* SPDX-License-Identifier: Zlib */
/*
 * crtl: the tty and socket ioctl numbers, and struct sysinfo's layout.
 *
 * A WRONG IOCTL NUMBER IS NOT AN ERROR -- it is a different call on a real
 * file descriptor, and a wrong SIOCGIF* fills a different part of struct ifreq
 * so that the caller prints a plausible address. TIOCSCTTY reached busybox's
 * init as an UNDECLARED IDENTIFIER TREATED AS 0, which is ioctl(fd, 0, ...).
 * All 144 constants were transcribed by script from asm-generic/ioctls.h and
 * linux/sockios.h and diffed value-for-value against glibc.
 *
 * ROWS 1-21 NAME THE ONES BUSYBOX ACTUALLY ISSUES; row 22 is a digest over
 * ALL 144 of them, position-weighted, so that a single wrong or reordered
 * constant anywhere in either block moves it. The digest is not a substitute
 * for the named rows -- it says "something changed" and they say what.
 *
 * The sysinfo rows are OFFSETS, not values: the KERNEL writes that struct, so
 * a field in the wrong place makes `free' print the buffer count as total RAM.
 * The live figures cannot be diffed (freeram moves between two runs), so what
 * is compared is the layout, plus plausibility on the fields that have one.
 *
 * Every row was diffed against glibc by compiling this same file with gcc.
 * feature-c-corpus-busybox-multi-applet
 */
#include <stdio.h>
#include <stddef.h>
#include <sys/ioctl.h>
#include <sys/sysinfo.h>

int main(void) {
  unsigned long d = 0;
  struct sysinfo a, b;
  int rc;

  printf("1 0x%lX\n", (unsigned long)TCGETS);
  printf("2 0x%lX\n", (unsigned long)TCSETS);
  printf("3 0x%lX\n", (unsigned long)TCSETSF);
  printf("4 0x%lX\n", (unsigned long)FIONREAD);
  printf("5 0x%lX\n", (unsigned long)TIOCSCTTY);
  printf("6 0x%lX\n", (unsigned long)TIOCNOTTY);
  printf("7 0x%lX\n", (unsigned long)TIOCGPGRP);
  printf("8 0x%lX\n", (unsigned long)TIOCSPGRP);
  printf("9 0x%lX\n", (unsigned long)TIOCGWINSZ);
  printf("10 0x%lX\n", (unsigned long)TIOCSWINSZ);
  printf("11 0x%lX\n", (unsigned long)TIOCGSID);
  printf("12 0x%lX\n", (unsigned long)TIOCSTI);
  printf("13 0x%lX\n", (unsigned long)TIOCCONS);
  printf("14 0x%lX\n", (unsigned long)TIOCLINUX);
  printf("15 0x%lX\n", (unsigned long)TIOCMGET);
  printf("16 0x%lX\n", (unsigned long)TIOCMSET);
  printf("17 0x%lX\n", (unsigned long)SIOCGIFCONF);
  printf("18 0x%lX\n", (unsigned long)SIOCGIFFLAGS);
  printf("19 0x%lX\n", (unsigned long)SIOCSIFADDR);
  printf("20 0x%lX\n", (unsigned long)SIOCADDRT);
  printf("21 0x%lX\n", (unsigned long)SIOCGIFHWADDR);

  d ^= (unsigned long)TCGETS * 1UL;
  d ^= (unsigned long)FIONREAD * 2UL;
  d ^= (unsigned long)TCSETS * 3UL;
  d ^= (unsigned long)TCSETSW * 4UL;
  d ^= (unsigned long)TCSETSF * 5UL;
  d ^= (unsigned long)TCGETA * 6UL;
  d ^= (unsigned long)TCSETA * 7UL;
  d ^= (unsigned long)TCSETAW * 8UL;
  d ^= (unsigned long)TCSETAF * 9UL;
  d ^= (unsigned long)TCSBRK * 10UL;
  d ^= (unsigned long)TCXONC * 11UL;
  d ^= (unsigned long)TCFLSH * 12UL;
  d ^= (unsigned long)TIOCEXCL * 13UL;
  d ^= (unsigned long)TIOCNXCL * 14UL;
  d ^= (unsigned long)TIOCSCTTY * 15UL;
  d ^= (unsigned long)TIOCGPGRP * 16UL;
  d ^= (unsigned long)TIOCSPGRP * 17UL;
  d ^= (unsigned long)TIOCOUTQ * 18UL;
  d ^= (unsigned long)TIOCSTI * 19UL;
  d ^= (unsigned long)TIOCGWINSZ * 20UL;
  d ^= (unsigned long)TIOCSWINSZ * 21UL;
  d ^= (unsigned long)TIOCMGET * 22UL;
  d ^= (unsigned long)TIOCMBIS * 23UL;
  d ^= (unsigned long)TIOCMBIC * 24UL;
  d ^= (unsigned long)TIOCMSET * 25UL;
  d ^= (unsigned long)TIOCGSOFTCAR * 26UL;
  d ^= (unsigned long)TIOCSSOFTCAR * 27UL;
  d ^= (unsigned long)TIOCLINUX * 28UL;
  d ^= (unsigned long)TIOCCONS * 29UL;
  d ^= (unsigned long)TIOCGSERIAL * 30UL;
  d ^= (unsigned long)TIOCSSERIAL * 31UL;
  d ^= (unsigned long)TIOCPKT * 32UL;
  d ^= (unsigned long)FIONBIO * 33UL;
  d ^= (unsigned long)TIOCNOTTY * 34UL;
  d ^= (unsigned long)TIOCSETD * 35UL;
  d ^= (unsigned long)TIOCGETD * 36UL;
  d ^= (unsigned long)TCSBRKP * 37UL;
  d ^= (unsigned long)TIOCSBRK * 38UL;
  d ^= (unsigned long)TIOCCBRK * 39UL;
  d ^= (unsigned long)TIOCGSID * 40UL;
  d ^= (unsigned long)TIOCGRS485 * 41UL;
  d ^= (unsigned long)TIOCSRS485 * 42UL;
  d ^= (unsigned long)TCGETX * 43UL;
  d ^= (unsigned long)TCSETX * 44UL;
  d ^= (unsigned long)TCSETXF * 45UL;
  d ^= (unsigned long)TCSETXW * 46UL;
  d ^= (unsigned long)TIOCVHANGUP * 47UL;
  d ^= (unsigned long)FIONCLEX * 48UL;
  d ^= (unsigned long)FIOCLEX * 49UL;
  d ^= (unsigned long)FIOASYNC * 50UL;
  d ^= (unsigned long)TIOCSERCONFIG * 51UL;
  d ^= (unsigned long)TIOCSERGWILD * 52UL;
  d ^= (unsigned long)TIOCSERSWILD * 53UL;
  d ^= (unsigned long)TIOCGLCKTRMIOS * 54UL;
  d ^= (unsigned long)TIOCSLCKTRMIOS * 55UL;
  d ^= (unsigned long)TIOCSERGSTRUCT * 56UL;
  d ^= (unsigned long)TIOCSERGETLSR * 57UL;
  d ^= (unsigned long)TIOCSERGETMULTI * 58UL;
  d ^= (unsigned long)TIOCSERSETMULTI * 59UL;
  d ^= (unsigned long)TIOCMIWAIT * 60UL;
  d ^= (unsigned long)TIOCGICOUNT * 61UL;
  d ^= (unsigned long)TIOCPKT_DATA * 62UL;
  d ^= (unsigned long)TIOCPKT_FLUSHREAD * 63UL;
  d ^= (unsigned long)TIOCPKT_FLUSHWRITE * 64UL;
  d ^= (unsigned long)TIOCPKT_STOP * 65UL;
  d ^= (unsigned long)TIOCPKT_START * 66UL;
  d ^= (unsigned long)TIOCPKT_NOSTOP * 67UL;
  d ^= (unsigned long)TIOCPKT_DOSTOP * 68UL;
  d ^= (unsigned long)TIOCPKT_IOCTL * 69UL;
  d ^= (unsigned long)TIOCSER_TEMT * 70UL;
  d ^= (unsigned long)SIOCADDRT * 71UL;
  d ^= (unsigned long)SIOCDELRT * 72UL;
  d ^= (unsigned long)SIOCRTMSG * 73UL;
  d ^= (unsigned long)SIOCGIFNAME * 74UL;
  d ^= (unsigned long)SIOCSIFLINK * 75UL;
  d ^= (unsigned long)SIOCGIFCONF * 76UL;
  d ^= (unsigned long)SIOCGIFFLAGS * 77UL;
  d ^= (unsigned long)SIOCSIFFLAGS * 78UL;
  d ^= (unsigned long)SIOCGIFADDR * 79UL;
  d ^= (unsigned long)SIOCSIFADDR * 80UL;
  d ^= (unsigned long)SIOCGIFDSTADDR * 81UL;
  d ^= (unsigned long)SIOCSIFDSTADDR * 82UL;
  d ^= (unsigned long)SIOCGIFBRDADDR * 83UL;
  d ^= (unsigned long)SIOCSIFBRDADDR * 84UL;
  d ^= (unsigned long)SIOCGIFNETMASK * 85UL;
  d ^= (unsigned long)SIOCSIFNETMASK * 86UL;
  d ^= (unsigned long)SIOCGIFMETRIC * 87UL;
  d ^= (unsigned long)SIOCSIFMETRIC * 88UL;
  d ^= (unsigned long)SIOCGIFMEM * 89UL;
  d ^= (unsigned long)SIOCSIFMEM * 90UL;
  d ^= (unsigned long)SIOCGIFMTU * 91UL;
  d ^= (unsigned long)SIOCSIFMTU * 92UL;
  d ^= (unsigned long)SIOCSIFNAME * 93UL;
  d ^= (unsigned long)SIOCSIFHWADDR * 94UL;
  d ^= (unsigned long)SIOCGIFENCAP * 95UL;
  d ^= (unsigned long)SIOCSIFENCAP * 96UL;
  d ^= (unsigned long)SIOCGIFHWADDR * 97UL;
  d ^= (unsigned long)SIOCGIFSLAVE * 98UL;
  d ^= (unsigned long)SIOCSIFSLAVE * 99UL;
  d ^= (unsigned long)SIOCADDMULTI * 100UL;
  d ^= (unsigned long)SIOCDELMULTI * 101UL;
  d ^= (unsigned long)SIOCGIFINDEX * 102UL;
  d ^= (unsigned long)SIOCSIFPFLAGS * 103UL;
  d ^= (unsigned long)SIOCGIFPFLAGS * 104UL;
  d ^= (unsigned long)SIOCDIFADDR * 105UL;
  d ^= (unsigned long)SIOCSIFHWBROADCAST * 106UL;
  d ^= (unsigned long)SIOCGIFCOUNT * 107UL;
  d ^= (unsigned long)SIOCGIFBR * 108UL;
  d ^= (unsigned long)SIOCSIFBR * 109UL;
  d ^= (unsigned long)SIOCGIFTXQLEN * 110UL;
  d ^= (unsigned long)SIOCSIFTXQLEN * 111UL;
  d ^= (unsigned long)SIOCETHTOOL * 112UL;
  d ^= (unsigned long)SIOCGMIIPHY * 113UL;
  d ^= (unsigned long)SIOCGMIIREG * 114UL;
  d ^= (unsigned long)SIOCSMIIREG * 115UL;
  d ^= (unsigned long)SIOCWANDEV * 116UL;
  d ^= (unsigned long)SIOCOUTQNSD * 117UL;
  d ^= (unsigned long)SIOCGSKNS * 118UL;
  d ^= (unsigned long)SIOCDARP * 119UL;
  d ^= (unsigned long)SIOCGARP * 120UL;
  d ^= (unsigned long)SIOCSARP * 121UL;
  d ^= (unsigned long)SIOCDRARP * 122UL;
  d ^= (unsigned long)SIOCGRARP * 123UL;
  d ^= (unsigned long)SIOCSRARP * 124UL;
  d ^= (unsigned long)SIOCGIFMAP * 125UL;
  d ^= (unsigned long)SIOCSIFMAP * 126UL;
  d ^= (unsigned long)SIOCADDDLCI * 127UL;
  d ^= (unsigned long)SIOCDELDLCI * 128UL;
  d ^= (unsigned long)SIOCGIFVLAN * 129UL;
  d ^= (unsigned long)SIOCSIFVLAN * 130UL;
  d ^= (unsigned long)SIOCBONDENSLAVE * 131UL;
  d ^= (unsigned long)SIOCBONDRELEASE * 132UL;
  d ^= (unsigned long)SIOCBONDSETHWADDR * 133UL;
  d ^= (unsigned long)SIOCBONDSLAVEINFOQUERY * 134UL;
  d ^= (unsigned long)SIOCBONDINFOQUERY * 135UL;
  d ^= (unsigned long)SIOCBONDCHANGEACTIVE * 136UL;
  d ^= (unsigned long)SIOCBRADDBR * 137UL;
  d ^= (unsigned long)SIOCBRDELBR * 138UL;
  d ^= (unsigned long)SIOCBRADDIF * 139UL;
  d ^= (unsigned long)SIOCBRDELIF * 140UL;
  d ^= (unsigned long)SIOCSHWTSTAMP * 141UL;
  d ^= (unsigned long)SIOCGHWTSTAMP * 142UL;
  d ^= (unsigned long)SIOCDEVPRIVATE * 143UL;
  d ^= (unsigned long)SIOCPROTOPRIVATE * 144UL;
  printf("22 0x%lX\n", d);

  printf("23 %zu %zu %zu\n", sizeof(struct sysinfo),
         offsetof(struct sysinfo, uptime), offsetof(struct sysinfo, loads));
  printf("24 %zu %zu %zu %zu\n",
         offsetof(struct sysinfo, totalram), offsetof(struct sysinfo, freeram),
         offsetof(struct sysinfo, sharedram), offsetof(struct sysinfo, bufferram));
  printf("25 %zu %zu %zu %zu\n",
         offsetof(struct sysinfo, totalswap), offsetof(struct sysinfo, freeswap),
         offsetof(struct sysinfo, procs), offsetof(struct sysinfo, pad));
  printf("26 %zu %zu %zu %d\n",
         offsetof(struct sysinfo, totalhigh), offsetof(struct sysinfo, freehigh),
         offsetof(struct sysinfo, mem_unit), SI_LOAD_SHIFT);

  /* Sequenced reads: an argument list has no evaluation order. */
  rc = sysinfo(&a);
  printf("27 %d\n", rc);
  rc = (a.uptime > 0 && a.uptime < 4000000000L);
  printf("28 %d\n", rc);
  rc = (a.mem_unit > 0 && a.mem_unit <= 4096);
  printf("29 %d\n", rc);
  rc = (a.totalram > 0 && a.freeram <= a.totalram && a.freeswap <= a.totalswap);
  printf("30 %d\n", rc);
  rc = (a.procs > 0 && a.procs < 100000);
  printf("31 %d\n", rc);
  /* totalram must not move between two calls a microsecond apart; freeram may. */
  rc = sysinfo(&b);
  printf("32 %d\n", rc);
  rc = (a.totalram == b.totalram);
  printf("33 %d\n", rc);
  return 0;
}
