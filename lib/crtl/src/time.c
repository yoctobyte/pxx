/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: time — libc-free calendar + wall/CPU clock.
 *
 * time()/clock() bridge to the Pascal PAL (__pxx_time / __pxx_clock in
 * lib/rtl/pxxcio.pas), which issues a per-arch clock_gettime syscall — so the
 * wall clock works uniformly across x86-64/i386/aarch64/arm32. The calendar
 * routines (gmtime/localtime/mktime/difftime/strftime) are pure integer math,
 * UTC-only (no timezone database), reused unchanged on every target. lua/sqlite
 * reference these; the small lua os-time tests do not currently exercise them,
 * but they must resolve as real symbols on the cross (libc-free) link.
 */

#include <time.h>

extern long long __pxx_time(void);
extern long long __pxx_clock(void);
extern int __pxx_nanosleep(long long sec, long long nsec);

/* nanosleep: suspend for req->tv_sec + req->tv_nsec. `rem` (unslept remainder on
   signal) is zeroed — the PAL bridge does not surface EINTR partial sleeps, which
   sqlite's busy-wait retry does not depend on. */
int nanosleep(const struct timespec *req, struct timespec *rem) {
  int r = __pxx_nanosleep((long long)req->tv_sec, (long long)req->tv_nsec);
  if (rem) { rem->tv_sec = 0; rem->tv_nsec = 0; }
  return r;
}

time_t time(time_t *t) {
  time_t now = (time_t)__pxx_time();
  if (t) *t = now;
  return now;
}

clock_t clock(void) { return (clock_t)__pxx_clock(); }

double difftime(time_t end, time_t beginning) {
  return (double)(end - beginning);
}

/* ---- civil-date <-> Unix-seconds (UTC) ---------------------------------- */
/* days_from_civil / civil_from_days: Howard Hinnant's proleptic-Gregorian
   algorithm, valid for the full 64-bit range. */

static long long days_from_civil(long long y, unsigned m, unsigned d) {
  y -= (m <= 2);
  long long era = (y >= 0 ? y : y - 399) / 400;
  unsigned yoe = (unsigned)(y - era * 400);
  unsigned doy = (153u * (m > 2 ? m - 3 : m + 9) + 2) / 5 + d - 1;
  unsigned doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
  return era * 146097 + (long long)doe - 719468;
}

static void civil_from_days(long long z, long long *y, unsigned *m, unsigned *d) {
  z += 719468;
  long long era = (z >= 0 ? z : z - 146096) / 146097;
  unsigned doe = (unsigned)(z - era * 146097);
  unsigned yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
  long long yy = (long long)yoe + era * 400;
  unsigned doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
  unsigned mp = (5 * doy + 2) / 153;
  *d = doy - (153 * mp + 2) / 5 + 1;
  *m = mp < 10 ? mp + 3 : mp - 9;
  *y = yy + (*m <= 2);
}

static struct tm tm_buf;   /* gmtime/localtime shared static (matches C ABI) */

struct tm *gmtime(const time_t *timer) {
  long long secs = (long long)*timer;
  long long days = secs / 86400;
  long long rem = secs % 86400;
  if (rem < 0) { rem += 86400; days -= 1; }

  tm_buf.tm_hour = (int)(rem / 3600);
  tm_buf.tm_min = (int)((rem % 3600) / 60);
  tm_buf.tm_sec = (int)(rem % 60);

  /* 1970-01-01 was a Thursday (wday 4). */
  int wd = (int)((days % 7 + 4) % 7);
  if (wd < 0) wd += 7;
  tm_buf.tm_wday = wd;

  long long y; unsigned m, d;
  civil_from_days(days, &y, &m, &d);
  tm_buf.tm_year = (int)(y - 1900);
  tm_buf.tm_mon = (int)m - 1;
  tm_buf.tm_mday = (int)d;
  tm_buf.tm_yday = (int)(days - days_from_civil(y, 1, 1));
  tm_buf.tm_isdst = 0;
  return &tm_buf;
}

/* No timezone database — local time == UTC. */
struct tm *localtime(const time_t *timer) { return gmtime(timer); }

time_t mktime(struct tm *tm) {
  long long y = (long long)tm->tm_year + 1900;
  long long days = days_from_civil(y, (unsigned)(tm->tm_mon + 1),
                                   (unsigned)tm->tm_mday);
  long long secs = days * 86400 + tm->tm_hour * 3600
                 + tm->tm_min * 60 + tm->tm_sec;
  /* normalize the struct back (best-effort, UTC). */
  time_t t = (time_t)secs;
  struct tm *n = gmtime(&t);
  *tm = *n;
  return t;
}

/* ---- strftime: the subset lua os.date emits ----------------------------- */

static const char *wday_abbr[7] =
  { "Sun","Mon","Tue","Wed","Thu","Fri","Sat" };
static const char *wday_full[7] =
  { "Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday" };
static const char *mon_abbr[12] =
  { "Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec" };
static const char *mon_full[12] =
  { "January","February","March","April","May","June","July","August",
    "September","October","November","December" };

static char *put_str(char *p, char *end, const char *s) {
  while (*s && p < end) *p++ = *s++;
  return p;
}

static char *put_num(char *p, char *end, int v, int width) {
  char tmp[16];
  int n = 0, neg = v < 0;
  unsigned u = neg ? (unsigned)(-v) : (unsigned)v;
  do { tmp[n++] = (char)('0' + u % 10); u /= 10; } while (u);
  while (n < width) tmp[n++] = '0';
  if (neg && p < end) *p++ = '-';
  while (n > 0 && p < end) *p++ = tmp[--n];
  return p;
}

size_t strftime(char *s, size_t max, const char *fmt, const struct tm *tm) {
  char *p = s;
  char *end = s + (max ? max - 1 : 0);
  int wd = tm->tm_wday & 7, mo = tm->tm_mon;
  if (wd < 0 || wd > 6) wd = 0;
  if (mo < 0 || mo > 11) mo = 0;

  while (*fmt) {
    if (*fmt != '%') { if (p < end) *p++ = *fmt; fmt++; continue; }
    fmt++;
    switch (*fmt) {
      case 'a': p = put_str(p, end, wday_abbr[wd]); break;
      case 'A': p = put_str(p, end, wday_full[wd]); break;
      case 'b': case 'h': p = put_str(p, end, mon_abbr[mo]); break;
      case 'B': p = put_str(p, end, mon_full[mo]); break;
      case 'd': p = put_num(p, end, tm->tm_mday, 2); break;
      case 'e': p = put_num(p, end, tm->tm_mday, 0); break;
      case 'H': p = put_num(p, end, tm->tm_hour, 2); break;
      case 'I': { int h = tm->tm_hour % 12; if (!h) h = 12;
                  p = put_num(p, end, h, 2); } break;
      case 'j': p = put_num(p, end, tm->tm_yday + 1, 3); break;
      case 'm': p = put_num(p, end, tm->tm_mon + 1, 2); break;
      case 'M': p = put_num(p, end, tm->tm_min, 2); break;
      case 'p': p = put_str(p, end, tm->tm_hour < 12 ? "AM" : "PM"); break;
      case 'S': p = put_num(p, end, tm->tm_sec, 2); break;
      case 'w': p = put_num(p, end, wd, 0); break;
      case 'y': p = put_num(p, end, (tm->tm_year + 1900) % 100, 2); break;
      case 'Y': p = put_num(p, end, tm->tm_year + 1900, 0); break;
      case '%': if (p < end) *p++ = '%'; break;
      case '\0': goto done;
      default: if (p < end) *p++ = '%';
               if (p < end) *p++ = *fmt; break;
    }
    fmt++;
  }
done:
  if (max) *p = '\0';
  return (size_t)(p - s);
}
