/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_TIME_H
#define PXX_CRTL_TIME_H 1

#include <stddef.h>   /* size_t, NULL */

/* Wall-clock seconds since the Unix epoch. 64-bit on every pxx target so the
   2038 problem never appears (lua stores time in lua_Integer, also 64-bit). */
typedef long long time_t;
typedef long long clock_t;

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

time_t time(time_t *t);
clock_t clock(void);
int nanosleep(const struct timespec *req, struct timespec *rem);
int clock_gettime(int clk_id, struct timespec *tp);
double difftime(time_t end, time_t beginning);
time_t mktime(struct tm *tm);
struct tm *gmtime(const time_t *timer);
struct tm *localtime(const time_t *timer);
size_t strftime(char *s, size_t max, const char *fmt, const struct tm *tm);

#endif
