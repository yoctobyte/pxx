/* Three crtl gaps busybox's own testsuite found on a pxx-built busybox
   (Nodisx, 2026-11-26):
   - getopt "o::": an optional argument is only an ATTACHED one; a bare -o
     leaves the next word an operand (sed -i SCRIPT FILE, xargs -e).
     bug-c-crtl-getopt-takes-the-next-word-as-an-optional-argument
   - localtime under a POSIX TZ rule string, DST included (busybox date).
     bug-c-crtl-localtime-ignores-a-posix-tz-rule-string
   - getaddrinfo/gethostbyname of a NAME, through /etc/hosts (hostname -i,
     wget). Only localhost: the test needs no network.
     bug-c-crtl-getaddrinfo-resolves-no-names
   Expected output is glibc's (post-1970 instants only: glibc's rule
   evaluation before 1970 is not the rule's). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <sys/socket.h>

static void opts(int argc, char **argv) {
  int c;
  optind = 1;
  printf("argv:");
  while ((c = getopt(argc, argv, "i::n")) != -1)
    printf(" -%c[%s]", c, optarg ? optarg : "null");
  for (; optind < argc; optind++) printf(" op=%s", argv[optind]);
  printf("\n");
}

static void tz(const char *z, long long t) {
  char b[64];
  time_t tt = (time_t)t;
  struct tm *tm;
  setenv("TZ", z, 1);
  tzset();
  tm = localtime(&tt);
  strftime(b, sizeof b, "%Y-%m-%d %H:%M:%S %Z", tm);
  printf("%s %lld: %s dst=%d timezone=%ld daylight=%d %s/%s\n", z, t, b, tm->tm_isdst,
         timezone, daylight, tzname[0], tzname[1]);
}

int main(void) {
  char *a1[] = { "sed", "-i", "s/x/y/", "file", 0 };
  char *a2[] = { "sed", "-i.bak", "-n", "s/x/y/", 0 };
  char *a3[] = { "xargs", "-i", 0 };
  struct addrinfo h, *r;
  struct hostent *he;
  int rc;

  opts(4, a1);
  opts(4, a2);
  opts(2, a3);

  tz("EET-2EEST,M3.5.0/3,M10.5.0/4", 1288486799);
  tz("EET-2EEST,M3.5.0/3,M10.5.0/4", 1288486801);
  tz("EET-2EEST,M3.5.0/3,M10.5.0/4", 1269737999);
  tz("EET-2EEST,M3.5.0/3,M10.5.0/4", 1269738001);
  tz("UTC-3", 0);
  tz("<+0330>-3:30", 1700000000);
  tz("EST5EDT,M3.2.0,M11.1.0", 1700000000);
  tz("AEST-10AEDT,M10.1.0,M4.1.0/3", 1700000000);
  tz("AEST-10AEDT,M10.1.0,M4.1.0/3", 1690000000);
  tz("CET-1CEST,J60/2,J300/3", 951782400);
  tz("NZST-12NZDT-13,M9.5.0,M4.1.0/3", 4102444800LL);

  he = gethostbyname("localhost");
  printf("gethostbyname(localhost): %s\n", he ? inet_ntoa(*(struct in_addr *)he->h_addr_list[0]) : "null");
  memset(&h, 0, sizeof h);
  h.ai_family = AF_INET;
  h.ai_socktype = SOCK_STREAM;
  rc = getaddrinfo("localhost", "80", &h, &r);
  printf("getaddrinfo(localhost): rc=%d %s:%d\n", rc,
         rc ? "-" : inet_ntoa(((struct sockaddr_in *)r->ai_addr)->sin_addr),
         rc ? 0 : ntohs(((struct sockaddr_in *)r->ai_addr)->sin_port));
  if (!rc) freeaddrinfo(r);
  h.ai_flags = AI_NUMERICHOST;
  rc = getaddrinfo("localhost", "80", &h, &r);
  printf("getaddrinfo(localhost, AI_NUMERICHOST): %s\n", rc == EAI_NONAME ? "EAI_NONAME" : "other");
  return 0;
}
