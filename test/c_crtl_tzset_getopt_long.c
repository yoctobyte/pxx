/* tzset(3) + its three globals, tcgetsid(3), gethostid(3), and getopt_long(3).
 *
 * All four are busybox gaps found by ATTEMPTING the 258-applet userland, not by
 * triage. tzset alone accounted for 8 of the 400 translation units; getopt_long
 * for one -- libbb/getopt32.c -- whose absence left `getopt32' and
 * `option_mask32' undefined and therefore took the WHOLE LINK down, which is
 * why one missing function was worth more than its file count.
 *
 * WHAT THIS FILE CAN AND CANNOT PIN. The getopt_long rows are pure argv
 * arithmetic and are pinned exactly. The zone rows use TZ=UTC and a
 * deliberately absent zone, because those are the two answers that do not
 * depend on a timezone database being installed; the REAL check on tzset ran
 * differentially against glibc over eight zones (UTC, Europe/Amsterdam,
 * America/New_York, Asia/Kolkata, Australia/Sydney, Africa/Nairobi,
 * America/Sao_Paulo, Pacific/Chatham) and matched tzname[0], tzname[1],
 * timezone and daylight in all eight -- including Kolkata, whose historic DST
 * record makes daylight 1 for a zone that has none today, and Chatham's
 * +12:45. A test that pinned CET here would fail on any box in another zone.
 * gethostid is the same story: measured equal to glibc's 007f0101 on this box,
 * where /etc/hosts maps the hostname to 127.0.1.1, and asserted here only for
 * the property that holds anywhere.
 *
 * Row 4 is the one that would catch the likely regression: `timezone' is
 * seconds WEST of UTC, the NEGATION of the offset a TZif stores, and a sign
 * error there still prints a plausible clock.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <time.h>
#include <termios.h>
#include <unistd.h>
#include <stdlib.h>
#include <getopt.h>

static int vflag;

int main(void)
{
  static struct option lo[] = {
    { "alpha",   no_argument,       0,      'a' },
    { "beta",    required_argument, 0,      'b' },
    { "verbose", no_argument,       &vflag, 7   },
    { "car",     no_argument,       0,      'c' },
    { "cart",    no_argument,       0,      'C' },
    { 0, 0, 0, 0 }
  };
  char *av[8];
  int c, li, n;
  long h1, h2;

  setenv("TZ", "UTC", 1);
  tzset();
  printf("1 %s %s %ld %d\n", tzname[0], tzname[1], timezone, daylight);

  /* A zone with no file: the offset must stay 0 and the clock must keep
     working. "A missing timezone database must not break the clock." */
  setenv("TZ", "Nowhere/Notazone", 1);
  tzset();
  printf("2 %ld %d\n", timezone, daylight);

  setenv("TZ", "UTC", 1);
  tzset();
  printf("3 %s\n", tzname[0]);
  printf("4 %d\n", timezone == 0);

  /* tcgetsid on something that is not a terminal: -1 and an errno, never a
     plausible session id. getty and sulogin branch on this.

     The two facts are read into locals FIRST and printed second, deliberately.
     Written as two arguments of one printf, the order in which they are
     evaluated is unspecified, so `errno != 0' may be read BEFORE the call that
     sets it -- and the first draft of this row did exactly that and printed a
     confident 0 on both compilers. Two builds agreeing about an unsequenced
     read is not an oracle; it is the same undefined answer twice. */
  {
    int rc, en;
    errno = 0;
    rc = (tcgetsid(-1) == (pid_t)-1);
    en = (errno != 0);
    printf("5 %d %d\n", rc, en);
  }

  /* gethostid: the portable property only -- it is a function of the machine,
     so it must be stable within a run. Its VALUE was checked against glibc
     separately; see the header. */
  h1 = gethostid(); h2 = gethostid();
  printf("6 %d\n", h1 == h2);

  /* getopt_long, five shapes: a long flag, a =value, a separate value, a
     unique prefix, and a table entry with a `flag' pointer (returns 0 and
     stores, rather than returning val). */
  av[0] = (char *)"prog"; av[1] = (char *)"--verbose"; av[2] = (char *)"--al";
  av[3] = (char *)"--beta=X"; av[4] = (char *)"--cart"; av[5] = (char *)"operand";
  av[6] = 0;
  n = 6;
  optind = 1;
  while ((c = getopt_long(n, av, "ab:cC", lo, &li)) != -1)
    printf("7 %d %s %d\n", c, optarg ? optarg : "-", vflag);
  printf("8 %s\n", optind < n ? av[optind] : "(none)");

  /* Short options still work through the same parser, including a cluster with
     an attached argument. This is the control that folding the two forms into
     one routine did not break the short one. */
  av[0] = (char *)"prog"; av[1] = (char *)"-ab"; av[2] = (char *)"Y"; av[3] = 0;
  n = 3;
  optind = 1;
  while ((c = getopt_long(n, av, "ab:", lo, &li)) != -1)
    printf("9 %c %s\n", c, optarg ? optarg : "-");

  return 0;
}
