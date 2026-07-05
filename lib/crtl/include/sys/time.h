/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_SYS_TIME_H
#define PXX_CRTL_SYS_TIME_H 1

/* Minimal sys/time surface for sqlite's unix VFS clock. Declarations only. */

#include <sys/types.h>

struct timeval {
  long tv_sec;
  long tv_usec;
};

struct timezone {
  int tz_minuteswest;
  int tz_dsttime;
};

extern int gettimeofday(struct timeval *tv, void *tz);
extern int utimes(const char *filename, const struct timeval times[2]);

#endif
