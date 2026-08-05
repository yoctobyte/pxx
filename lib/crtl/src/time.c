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
#include <stdlib.h>   /* getenv, for $TZ */

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

/* Defined under the __crtl_ name — see the note in include/time.h. */
time_t __crtl_time(time_t *t) {
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

/* ---- timezone: the UTC offset in effect at an instant --------------------
 *
 * localtime() used to be gmtime(), so every local timestamp a program printed
 * was UTC — silently, since 22:13 is as plausible as 23:13. Measured against
 * gcc: Europe/Amsterdam was off by an hour, America/New_York by five.
 *
 * The source is the TZif file (RFC 8536) that $TZ or /etc/localtime names, NOT
 * the POSIX TZ rule string. That is deliberate: parsing a TZ string's leading
 * offset while skipping its DST rule gives an answer right for half the year
 * and wrong for the other half with nothing to say which, which is worse than
 * an honest uniform UTC. A TZif file carries PRECOMPUTED transitions, so DST
 * falls out of a binary search rather than rule evaluation.
 *
 * If anything fails — no file, unreadable, bad magic, truncated — the offset is
 * 0 and behaviour is exactly what it was before. A missing timezone database
 * must not break the clock. */

#define PXX_TZ_BUFSZ 8192

static char pxx_tz_buf[PXX_TZ_BUFSZ];
static long pxx_tz_len = 0;
static int pxx_tz_loaded = 0;

extern int __pxx_open(const char *path, int flags, int mode);
extern long __pxx_read(int fd, void *buf, unsigned long n);
extern int __pxx_close(int fd);

/* TZif counts are UNSIGNED 32-bit; utoff is SIGNED. Two readers, because one
   that ignored the difference made America/New_York's -18000 (0xFFFFB9B0) read
   back as 4294948784 on a 64-bit long — and Europe/Amsterdam's +3600 still
   worked, so a one-zone test would have passed. */
static long pxx_be32u(const unsigned char *p) {
  return ((long)p[0] << 24) | ((long)p[1] << 16) | ((long)p[2] << 8) | (long)p[3];
}

static long pxx_be32s(const unsigned char *p) {
  long v = pxx_be32u(p);
  if (v & 0x80000000L) v -= 0x100000000L;      /* sign-extend the int32 */
  return v;
}

static long long pxx_be64(const unsigned char *p) {
  long long v = 0; int i;
  for (i = 0; i < 8; i++) v = (v << 8) | (long long)p[i];
  return v;
}

/* Read $TZ's zoneinfo file, else /etc/localtime. A TZ of "UTC" needs no file
   and is the common case in test harnesses, so it short-circuits. */
static void pxx_tz_load(void) {
  int fd; long got; const char *tz;
  char path[256]; int i, j;
  if (pxx_tz_loaded) return;
  pxx_tz_loaded = 1;
  tz = getenv("TZ");
  if (tz && tz[0] == 'U' && tz[1] == 'T' && tz[2] == 'C' && tz[3] == 0) return;
  if (tz && tz[0] && tz[0] != ':') {
    const char *pre = "/usr/share/zoneinfo/";
    for (i = 0; pre[i]; i++) path[i] = pre[i];
    for (j = 0; tz[j] && i + j + 1 < (int)sizeof(path); j++) path[i + j] = tz[j];
    path[i + j] = 0;
    fd = __pxx_open(path, 0, 0);
  } else {
    fd = __pxx_open("/etc/localtime", 0, 0);
  }
  if (fd < 0) return;
  got = __pxx_read(fd, pxx_tz_buf, PXX_TZ_BUFSZ);
  __pxx_close(fd);
  if (got > 0) pxx_tz_len = got;
}

/* The UTC offset in seconds at `t`, from the loaded TZif. 0 on any problem. */
static long pxx_tz_offset(long long t) {
  const unsigned char *b = (const unsigned char *)pxx_tz_buf;
  long len, isutcnt, isstdcnt, leapcnt, timecnt, typecnt, charcnt;
  long off, v1size, i, lo, hi, idx;
  int ver;
  pxx_tz_load();
  len = pxx_tz_len;
  if (len < 44) return 0;
  if (b[0] != 'T' || b[1] != 'Z' || b[2] != 'i' || b[3] != 'f') return 0;
  ver = b[4];

  isutcnt = pxx_be32u(b + 20); isstdcnt = pxx_be32u(b + 24);
  leapcnt = pxx_be32u(b + 28); timecnt  = pxx_be32u(b + 32);
  typecnt = pxx_be32u(b + 36); charcnt  = pxx_be32u(b + 40);

  if (ver == '2' || ver == '3' || ver == '4') {
    /* skip the 32-bit block and its header, then re-read the 64-bit counts */
    v1size = 44 + timecnt * 4 + timecnt + typecnt * 6 + charcnt
           + leapcnt * 8 + isstdcnt + isutcnt;
    if (v1size + 44 > len) return 0;
    b += v1size;
    len -= v1size;
    if (b[0] != 'T' || b[1] != 'Z' || b[2] != 'i' || b[3] != 'f') return 0;
    isutcnt = pxx_be32u(b + 20); isstdcnt = pxx_be32u(b + 24);
    leapcnt = pxx_be32u(b + 28); timecnt  = pxx_be32u(b + 32);
    typecnt = pxx_be32u(b + 36); charcnt  = pxx_be32u(b + 40);
    off = 44;
    if (off + timecnt * 8 + timecnt + typecnt * 6 > len) return 0;
    /* largest transition <= t; before the first, use type 0 */
    idx = -1;
    lo = 0; hi = timecnt - 1;
    while (lo <= hi) {
      long mid = lo + (hi - lo) / 2;
      if (pxx_be64(b + off + mid * 8) <= t) { idx = mid; lo = mid + 1; }
      else hi = mid - 1;
    }
    if (idx < 0) i = 0;
    else i = b[off + timecnt * 8 + idx];
    if (i < 0 || i >= typecnt) return 0;
    return pxx_be32s(b + off + timecnt * 8 + timecnt + i * 6);
  }

  /* version 1: 32-bit transitions */
  off = 44;
  if (off + timecnt * 4 + timecnt + typecnt * 6 > len) return 0;
  idx = -1;
  for (i = 0; i < timecnt; i++) {
    long tt = pxx_be32s(b + off + i * 4);
    if ((long long)tt <= t) idx = i; else break;
  }
  if (idx < 0) i = 0;
  else i = b[off + timecnt * 4 + idx];
  if (i < 0 || i >= typecnt) return 0;
  return pxx_be32s(b + off + timecnt * 4 + timecnt + i * 6);
}

struct tm *localtime(const time_t *timer) {
  time_t shifted;
  if (!timer) return gmtime(timer);
  shifted = (time_t)(*timer + (time_t)pxx_tz_offset((long long)*timer));
  return gmtime(&shifted);
}

/* Reentrant variants (POSIX): fill the caller's buffer, no shared static. */
struct tm *gmtime_r(const time_t *timer, struct tm *result) {
  *result = *gmtime(timer);
  return result;
}
struct tm *localtime_r(const time_t *timer, struct tm *result) {
  *result = *localtime(timer);
  return result;
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

/* ---- asctime / ctime / timegm ------------------------------------------- */

/* timegm(3): the inverse of gmtime — a struct tm interpreted as UTC, with the
   struct normalised in place. crtl's mktime is already UTC (there is no
   local-time offset in the PAL), so this is the same computation under the name
   that actually PROMISES UTC; code that means UTC should not have to rely on
   mktime happening to be. Was missing entirely — a program calling it hit
   "call to undeclared function". */
time_t timegm(struct tm *tm) {
  return mktime(tm);
}

/* asctime(3) / ctime(3), C99 7.23.3.1. The format is FIXED by the standard —
   "Www Mmm dd hh:mm:ss yyyy\n", 26 bytes with the NUL, mday space-padded and
   the time fields zero-padded — so this is written out literally rather than
   through strftime, which has no %e-with-leading-space-in-a-fixed-layout form.
   Both were missing; ctime(&t) is the one-liner everyone reaches for first. */
static char asctime_buf[32];

static char *two_digits(char *p, int v, char pad) {
  if (v < 0 || v > 99) v = 0;
  *p++ = (v < 10) ? pad : (char)('0' + v / 10);
  *p++ = (char)('0' + v % 10);
  return p;
}

char *asctime_r(const struct tm *tm, char *buf) {
  int wd = tm->tm_wday, mo = tm->tm_mon, year = tm->tm_year + 1900;
  char *p = buf;
  int i, neg = 0;
  char yb[16];
  int yn = 0;
  if (wd < 0 || wd > 6) wd = 0;
  if (mo < 0 || mo > 11) mo = 0;
  for (i = 0; i < 3; i++) *p++ = wday_abbr[wd][i];
  *p++ = ' ';
  for (i = 0; i < 3; i++) *p++ = mon_abbr[mo][i];
  *p++ = ' ';
  p = two_digits(p, tm->tm_mday, ' ');     /* SPACE-padded, not zero-padded */
  *p++ = ' ';
  p = two_digits(p, tm->tm_hour, '0');
  *p++ = ':';
  p = two_digits(p, tm->tm_min, '0');
  *p++ = ':';
  p = two_digits(p, tm->tm_sec, '0');
  *p++ = ' ';
  if (year < 0) { neg = 1; year = -year; }
  do { yb[yn++] = (char)('0' + year % 10); year /= 10; } while (year);
  while (yn < 4) yb[yn++] = '0';           /* the standard layout is 4 digits */
  if (neg) *p++ = '-';
  while (yn > 0) *p++ = yb[--yn];
  *p++ = '\n';
  *p = '\0';
  return buf;
}

char *asctime(const struct tm *tm) {
  return asctime_r(tm, asctime_buf);
}

char *ctime_r(const time_t *timer, char *buf) {
  return asctime_r(localtime(timer), buf);
}

char *ctime(const time_t *timer) {
  return asctime(localtime(timer));
}

/* `trunc` is set when a byte could not be written. strftime must return 0 on
   overflow (C99 7.23.3.5) rather than the truncated length, so every writer has
   to say whether it dropped anything — silently stopping at `end` is what made
   strftime(b, 4, "%Y", ...) return 3 and hand back "200" as if it were a year. */
static char *put_str(char *p, char *end, const char *s, int *trunc) {
  while (*s) {
    if (p < end) *p++ = *s++;
    else { *trunc = 1; return p; }
  }
  return p;
}

static char *put_num(char *p, char *end, int v, int width, int *trunc) {
  char tmp[16];
  int n = 0, neg = v < 0;
  unsigned u = neg ? (unsigned)(-v) : (unsigned)v;
  do { tmp[n++] = (char)('0' + u % 10); u /= 10; } while (u);
  while (n < width) tmp[n++] = '0';
  if (neg) { if (p < end) *p++ = '-'; else { *trunc = 1; return p; } }
  while (n > 0) {
    if (p < end) *p++ = tmp[--n];
    else { *trunc = 1; return p; }
  }
  return p;
}

size_t strftime(char *s, size_t max, const char *fmt, const struct tm *tm) {
  char *p = s;
  char *end = s + (max ? max - 1 : 0);
  int wd = tm->tm_wday & 7, mo = tm->tm_mon;
  int trunc = 0;
  if (wd < 0 || wd > 6) wd = 0;
  if (mo < 0 || mo > 11) mo = 0;
  if (max == 0) return 0;

  while (*fmt) {
    if (*fmt != '%') { if (p < end) *p++ = *fmt; else { trunc = 1; break; } fmt++; continue; }
    fmt++;
    switch (*fmt) {
      case 'a': p = put_str(p, end, wday_abbr[wd], &trunc); break;
      case 'A': p = put_str(p, end, wday_full[wd], &trunc); break;
      case 'b': case 'h': p = put_str(p, end, mon_abbr[mo], &trunc); break;
      case 'B': p = put_str(p, end, mon_full[mo], &trunc); break;
      case 'd': p = put_num(p, end, tm->tm_mday, 2, &trunc); break;
      case 'e': p = put_num(p, end, tm->tm_mday, 0, &trunc); break;
      case 'H': p = put_num(p, end, tm->tm_hour, 2, &trunc); break;
      case 'I': { int h = tm->tm_hour % 12; if (!h) h = 12;
                  p = put_num(p, end, h, 2, &trunc); } break;
      case 'j': p = put_num(p, end, tm->tm_yday + 1, 3, &trunc); break;
      case 'm': p = put_num(p, end, tm->tm_mon + 1, 2, &trunc); break;
      case 'M': p = put_num(p, end, tm->tm_min, 2, &trunc); break;
      case 'p': p = put_str(p, end, tm->tm_hour < 12 ? "AM" : "PM", &trunc); break;
      case 'S': p = put_num(p, end, tm->tm_sec, 2, &trunc); break;
      case 'w': p = put_num(p, end, wd, 0, &trunc); break;
      case 'y': p = put_num(p, end, (tm->tm_year + 1900) % 100, 2, &trunc); break;
      case 'Y': p = put_num(p, end, tm->tm_year + 1900, 0, &trunc); break;
      case '%': if (p < end) *p++ = '%'; else trunc = 1; break;
      case '\0': goto done;
      default: if (p < end) *p++ = '%'; else trunc = 1;
               if (!trunc) { if (p < end) *p++ = *fmt; else trunc = 1; }
               break;
    }
    if (trunc) break;
    fmt++;
  }
done:
  /* C99 7.23.3.5: when the result including the terminating null does not fit
     in `max`, return 0 — the array contents are then unspecified. Returning
     (p - s) handed the caller a TRUNCATED string with a plausible length, so
     `strftime(b, 4, "%Y", t)` looked like a successful 3-char year "200". */
  if (trunc) { *s = '\0'; return 0; }
  *p = '\0';
  return (size_t)(p - s);
}

/* gettimeofday lives in sys/time.c, which is where <sys/time.h> declares it and
   where the microsecond-precision PAL bridge (__pxx_realtime) is. A second,
   second-precision-only body used to sit here — tv_usec always 0 — and since
   this file includes <sys/time.h> both were compiled into the same TU, so which
   precision a caller got depended on pull order. Found by the C duplicate-
   definition warning (bug-c-string-h-compiles-stdlib-c-twice). */

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
