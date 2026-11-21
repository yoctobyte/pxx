/* mktime is the inverse of localtime, in the zone TZ names; strptime knows %C.
   Run once per zone with TZ in the environment, against gcc (Makefile).

   Both were toybox suite failures (bug-c-toybox-test-suite-failures):
   crtl's mktime read the fields as UTC, so `touch -t 01231234' stamped 13:34
   on a CET box, and strptime had no %C, so every `touch -t CCYYMMDDhhmm' was
   a "bad date". */
#define _XOPEN_SOURCE 700
#include <stdio.h>
#include <string.h>
#include <time.h>

static void mk(int y, int mo, int d, int h, int mi, int s, int isdst)
{
  struct tm tm;
  time_t t;
  memset(&tm, 0, sizeof tm);
  tm.tm_year = y - 1900; tm.tm_mon = mo - 1; tm.tm_mday = d;
  tm.tm_hour = h; tm.tm_min = mi; tm.tm_sec = s; tm.tm_isdst = isdst;
  t = mktime(&tm);
  printf("mktime %04d-%02d-%02d %02d:%02d:%02d isdst=%2d -> %lld"
         "  norm %04d-%02d-%02d %02d:%02d:%02d dst=%d wday=%d yday=%d\n",
         y, mo, d, h, mi, s, isdst, (long long)t,
         tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday, tm.tm_hour, tm.tm_min,
         tm.tm_sec, tm.tm_isdst, tm.tm_wday, tm.tm_yday);
}

static void roundtrip(long long t0)
{
  time_t t = (time_t)t0;
  struct tm tm = *localtime(&t);
  tm.tm_isdst = -1;
  printf("roundtrip %lld -> %lld\n", t0, (long long)mktime(&tm));
}

static void sp(const char *s, const char *f)
{
  struct tm tm;
  char *p;
  memset(&tm, 0, sizeof tm);
  tm.tm_year = 126;
  p = strptime(s, f, &tm);
  printf("strptime %-16s %-14s -> %s rest=[%s] year=%d mon=%d mday=%d %02d:%02d:%02d\n",
         s, f, p ? "ok" : "NULL", p ? p : "", tm.tm_year + 1900,
         tm.tm_mon + 1, tm.tm_mday, tm.tm_hour, tm.tm_min, tm.tm_sec);
}

int main(void)
{
  tzset();
  mk(2026, 1, 23, 12, 34, 0, -1);
  mk(2026, 1, 23, 12, 34, 0, 0);
  mk(2026, 7, 1, 12, 0, 0, -1);
  mk(2026, 7, 1, 12, 0, 0, 1);
  mk(2012, 1, 23, 12, 34, 56, -1);
  mk(2001, 9, 9, 1, 46, 40, -1);
  mk(1970, 1, 1, 0, 0, 0, -1);
  mk(2026, 1, 31, 25, 70, 0, -1);    /* out-of-range fields normalise */
  mk(2026, 13, 1, 0, 0, 0, -1);
  /* an hour well clear of every zone's DST changes on both sides */
  mk(2026, 4, 15, 9, 30, 0, -1);
  mk(2026, 11, 15, 9, 30, 0, -1);
  roundtrip(0);
  roundtrip(1000000000);
  roundtrip(1769168040);
  roundtrip(1782900000);
  sp("201201231234", "%C%y%m%d%H%M");
  sp("201201231234.56", "%C%y%m%d%H%M");
  sp("2101231234", "%y%m%d%H%M");
  sp("2012", "%C%y");
  sp("1999", "%C%y");
  sp("20", "%C");
  sp("12", "%y");
  sp("70", "%y");
  sp("68", "%y");
  sp("12 20", "%y %C");
  /* NOT tested: %C/%y together with a later %Y. POSIX leaves conflicting
     conversions unspecified, and glibc's answer (1900) is its bookkeeping. */
  return 0;
}
