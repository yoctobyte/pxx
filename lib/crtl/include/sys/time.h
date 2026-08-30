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

/* settimeofday: DECLARED and defined, but it always fails with -1/ENOSYS — the
   PAL exposes no clock_settime/settimeofday syscall. It exists so a program
   carrying a code path it never takes can still link; see the note beside the
   other ENOSYS stubs in lib/crtl/src/unistd.c. A caller that does take the
   path gets an error, never a clock that silently did not move. */
extern int settimeofday(const struct timeval *tv, const struct timezone *tz);

#endif
