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
#include <sys/time.h>

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

/* Reentrant variants (POSIX): fill the caller's buffer, no shared static. */
struct tm *gmtime_r(const time_t *timer, struct tm *result) {
  *result = *gmtime(timer);
  return result;
}
struct tm *localtime_r(const time_t *timer, struct tm *result) {
  return gmtime_r(timer, result);
}

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

/* gettimeofday: wall clock via the PAL. Second precision only (__pxx_time
   discards sub-second), so tv_usec is always 0 — enough for Date.now()/VFS
   timestamps, not a high-resolution timer. */
int gettimeofday(struct timeval *tv, void *tz) {
  (void)tz;
  if (tv) { tv->tv_sec = (long)__pxx_time(); tv->tv_usec = 0; }
  return 0;
}

/* --- strptime: parse a broken-down time from a string (POSIX). ------------ */

static int sp_ci_eq(char a, char b) {
  if (a >= 'A' && a <= 'Z') a = (char)(a - 'A' + 'a');
  if (b >= 'A' && b <= 'Z') b = (char)(b - 'A' + 'a');
  return a == b;
}

/* Match one of `names` (case-insensitive, prefix) at *sp; on success advance
   *sp past the match, store the 0-based index in *out, return 1. */
static int sp_match_name(const char **sp, const char *const *names, int n, int *out) {
  int i;
  for (i = 0; i < n; i++) {
    const char *s = *sp, *t = names[i];
    while (*t && sp_ci_eq(*s, *t)) { s++; t++; }
    if (*t == '\0') { *sp = s; *out = i; return 1; }
  }
  return 0;
}

/* Read up to `maxw` decimal digits (skipping leading spaces) into *out. */
static int sp_num(const char **sp, int maxw, int *out) {
  const char *s = *sp;
  int v = 0, got = 0;
  while (*s == ' ' || *s == '\t') s++;
  while (got < maxw && *s >= '0' && *s <= '9') { v = v * 10 + (*s - '0'); s++; got++; }
  if (!got) return 0;
  *sp = s; *out = v; return 1;
}

static const char *sp_parse(const char *s, const char *fmt, struct tm *tm);

char *strptime(const char *s, const char *fmt, struct tm *tm) {
  const char *r = sp_parse(s, fmt, tm);
  return (char *)r;   /* NULL on mismatch */
}

static const char *sp_parse(const char *s, const char *fmt, struct tm *tm) {
  int v, idx;
  while (*fmt) {
    if (*fmt == '%') {
      fmt++;
      switch (*fmt) {
        case 'a': case 'A':
          if (!sp_match_name(&s, wday_full, 7, &idx) &&
              !sp_match_name(&s, wday_abbr, 7, &idx)) return 0;
          tm->tm_wday = idx; break;
        case 'b': case 'B': case 'h':
          if (!sp_match_name(&s, mon_full, 12, &idx) &&
              !sp_match_name(&s, mon_abbr, 12, &idx)) return 0;
          tm->tm_mon = idx; break;
        case 'd': case 'e':
          if (!sp_num(&s, 2, &v)) return 0; tm->tm_mday = v; break;
        case 'H': if (!sp_num(&s, 2, &v)) return 0; tm->tm_hour = v; break;
        case 'I': if (!sp_num(&s, 2, &v)) return 0; tm->tm_hour = v % 12; break;
        case 'j': if (!sp_num(&s, 3, &v)) return 0; tm->tm_yday = v - 1; break;
        case 'm': if (!sp_num(&s, 2, &v)) return 0; tm->tm_mon = v - 1; break;
        case 'M': if (!sp_num(&s, 2, &v)) return 0; tm->tm_min = v; break;
        case 'S': if (!sp_num(&s, 2, &v)) return 0; tm->tm_sec = v; break;
        case 'y': if (!sp_num(&s, 2, &v)) return 0;
                  tm->tm_year = v < 69 ? v + 100 : v; break;
        case 'Y': if (!sp_num(&s, 4, &v)) return 0; tm->tm_year = v - 1900; break;
        case 'p':
          if (sp_ci_eq(s[0], 'p') && sp_ci_eq(s[1], 'm')) { if (tm->tm_hour < 12) tm->tm_hour += 12; s += 2; }
          else if (sp_ci_eq(s[0], 'a') && sp_ci_eq(s[1], 'm')) { if (tm->tm_hour == 12) tm->tm_hour = 0; s += 2; }
          else return 0;
          break;
        case 'c':   /* locale date+time: "Www Mmm dd hh:mm:ss yyyy" */
          s = sp_parse(s, "%a %b %e %H:%M:%S %Y", tm);
          if (!s) return 0; break;
        case 'n': case 't':
          while (*s == ' ' || *s == '\t' || *s == '\n') s++; break;
        case '%':
          if (*s != '%') return 0; s++; break;
        case '\0': return s;
        default: return 0;   /* unsupported specifier */
      }
      fmt++;
    } else if (*fmt == ' ' || *fmt == '\t' || *fmt == '\n') {
      while (*s == ' ' || *s == '\t' || *s == '\n') s++;
      fmt++;
    } else {
      if (*s != *fmt) return 0;
      s++; fmt++;
    }
  }
  return s;
}
