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

/* The BSD struct timeval macros, as glibc defines them (default __USE_MISC).
   timercmp takes the comparison OPERATOR as its third argument; it is not a
   function and cannot be one. */
#define timerisset(tvp)  ((tvp)->tv_sec || (tvp)->tv_usec)
#define timerclear(tvp)  ((tvp)->tv_sec = (tvp)->tv_usec = 0)
#define timercmp(a, b, CMP)                                   \
  (((a)->tv_sec == (b)->tv_sec)                               \
     ? ((a)->tv_usec CMP (b)->tv_usec)                        \
     : ((a)->tv_sec CMP (b)->tv_sec))
#define timeradd(a, b, result)                                \
  do {                                                        \
    (result)->tv_sec = (a)->tv_sec + (b)->tv_sec;             \
    (result)->tv_usec = (a)->tv_usec + (b)->tv_usec;          \
    if ((result)->tv_usec >= 1000000) {                       \
      ++(result)->tv_sec;                                     \
      (result)->tv_usec -= 1000000;                           \
    }                                                         \
  } while (0)
#define timersub(a, b, result)                                \
  do {                                                        \
    (result)->tv_sec = (a)->tv_sec - (b)->tv_sec;             \
    (result)->tv_usec = (a)->tv_usec - (b)->tv_usec;          \
    if ((result)->tv_usec < 0) {                              \
      --(result)->tv_sec;                                     \
      (result)->tv_usec += 1000000;                           \
    }                                                         \
  } while (0)

#endif
