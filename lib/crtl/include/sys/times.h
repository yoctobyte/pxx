/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_SYS_TIMES_H
#define PXX_CRTL_SYS_TIMES_H 1

#include <time.h>   /* clock_t */

/* Filled by the kernel. The member type is an ABI fact, not a choice -- see the
   clock_t comment in <time.h>. */
struct tms {
  clock_t tms_utime;   /* user CPU time                */
  clock_t tms_stime;   /* system CPU time              */
  clock_t tms_cutime;  /* user CPU time of reaped children   */
  clock_t tms_cstime;  /* system CPU time of reaped children */
};

/* Returns ticks since an arbitrary point in the past -- NOT 0 on success -- or
   (clock_t)-1 with errno set. Divide by sysconf(_SC_CLK_TCK) for seconds. */
clock_t times(struct tms *buf);

#endif
