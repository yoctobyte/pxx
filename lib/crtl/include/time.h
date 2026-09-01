/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_TIME_H
#define PXX_CRTL_TIME_H 1

#include <stddef.h>   /* size_t, NULL */

/* Wall-clock seconds since the Unix epoch. 64-bit on every pxx target so the
   2038 problem never appears (lua stores time in lua_Integer, also 64-bit). */
typedef long long time_t;
/* `long', matching glibc/Linux, NOT `long long'. This is an ABI fact rather
   than a preference: `struct tms' is filled by the KERNEL with four
   target-word-sized clock_t, and real code indexes it by byte offset and reads
   through a clock_t pointer -- busybox's ash does exactly that
   (`*(clock_t *)((char *)&buf + offset)'). A clock_t wider than the member
   reads two fields as one, silently, on every 32-bit target. It was
   `long long' here, which is the same width on x86-64 and aarch64 and wrong on
   i386, arm32, riscv32 and xtensa -- the shape that passes where you test. */
typedef long clock_t;

/* clock() reports process CPU time in these units (see lib/crtl/src/time.c). */
#define CLOCKS_PER_SEC 1000000L

struct tm {
  int tm_sec;    /* 0..60 (leap second) */
  int tm_min;    /* 0..59 */
  int tm_hour;   /* 0..23 */
  int tm_mday;   /* 1..31 */
  int tm_mon;    /* 0..11 */
  int tm_year;   /* years since 1900 */
  int tm_wday;   /* 0..6, Sunday = 0 */
  int tm_yday;   /* 0..365 */
  int tm_isdst;  /* daylight-saving flag (always 0 — pxx crtl is UTC) */
};

struct timespec {
  long tv_sec;
  long tv_nsec;
};

#define CLOCK_REALTIME  0
#define CLOCK_MONOTONIC 1

/* The C name `time` collides case-insensitively with sysutils' Pascal `Time`
   when the RTL is linked next to crtl, and cfront's FindProc spans both
   namespaces — so `time(NULL)` bound to the Pascal function (no parameters,
   Double result) and any C unit that read the clock crashed as soon as the
   program also used sysutils (bug-c-unit-crashes-when-sysutils-is-used).
   Same cure as exp/Exp in math.h: the implementation lives under __crtl_time
   and C callers reach it through a FUNCTION-LIKE macro, so variables and
   struct fields named `time` are untouched. */
extern time_t __crtl_time(time_t *t);
#define time(t) __crtl_time(t)
clock_t clock(void);
int nanosleep(const struct timespec *req, struct timespec *rem);
int clock_gettime(int clk_id, struct timespec *tp);
double difftime(time_t end, time_t beginning);
time_t mktime(struct tm *tm);
struct tm *gmtime(const time_t *timer);
struct tm *localtime(const time_t *timer);
struct tm *gmtime_r(const time_t *timer, struct tm *result);
struct tm *localtime_r(const time_t *timer, struct tm *result);
size_t strftime(char *s, size_t max, const char *fmt, const struct tm *tm);
char *strptime(const char *s, const char *fmt, struct tm *tm);
time_t timegm(struct tm *tm);
char *asctime(const struct tm *tm);
char *asctime_r(const struct tm *tm, char *buf);
char *ctime(const time_t *timer);
char *ctime_r(const time_t *timer, char *buf);

#endif
