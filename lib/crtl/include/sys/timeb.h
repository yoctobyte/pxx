/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <sys/timeb.h>, the old ftime(): the time in seconds and
 * milliseconds. Removed from POSIX in 2008, still included by GNU make's
 * makeint.h whenever configure finds it. timezone and dstflag are 0, as
 * glibc fills them: the kernel keeps no zone.
 */
#ifndef _CRTL_SYS_TIMEB_H
#define _CRTL_SYS_TIMEB_H
#include <time.h>

struct timeb {
  time_t time;              /* seconds since the Epoch */
  unsigned short millitm;   /* milliseconds, 0..999 */
  short timezone;           /* minutes west of Greenwich: 0 */
  short dstflag;            /* 0 */
};

int ftime(struct timeb *tp);

#endif
