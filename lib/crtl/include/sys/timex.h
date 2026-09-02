/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <sys/timex.h> -- adjtimex(2), the kernel's clock discipline.
 *
 * EVERY FIELD BELOW IS `long' AND THAT IS AN ABI DECISION, not a shorthand.
 * The kernel's i386 adjtimex takes a struct of 32-bit longs with a 32-bit
 * `struct timeval' inside it; crtl's time_t is `long' for exactly that reason
 * (see <time.h>), so this struct is the kernel's on both widths without a
 * per-architecture arm. glibc needs one because it offers a 64-bit-time_t
 * i386, which crtl does not.
 *
 * The struct ENDS IN ELEVEN PADDING WORDS and they are not decoration: the
 * kernel copies sizeof(struct timex) bytes each way, so a version that dropped
 * them reads and writes a short struct. That does not fail -- adjtimex
 * succeeds, and the fields the kernel wrote past the end are the caller's
 * stack.
 *
 * ADJ_OFFSET_SINGLESHOT IS 0x8001, NOT 0x8000: it carries ADJ_OFFSET's bit as
 * well, so a caller ORing it with ADJ_OFFSET is doing nothing new and one that
 * writes 0x8000 instead has asked for nothing at all. MOD_CLKA is the same
 * value under an older name, and glibc's own comment says "0x8000 in original".
 *
 * Found attempting busybox on i386: miscutils/adjtimex.c and networking/ntpd.c.
 * feature-c-corpus-busybox-i386-the-second-architecture
 */
#ifndef _CRTL_SYS_TIMEX_H
#define _CRTL_SYS_TIMEX_H

#include <sys/time.h>

#define NTP_API 4   /* NTP API version */

struct timex {
  unsigned int modes;   /* mode selector */
  long offset;          /* time offset (usec) */
  long freq;            /* frequency offset (scaled ppm) */
  long maxerror;        /* maximum error (usec) */
  long esterror;        /* estimated error (usec) */
  int  status;          /* clock command/status */
  long constant;        /* pll time constant */
  long precision;       /* clock precision (usec) (ro) */
  long tolerance;       /* clock frequency tolerance (ppm) (ro) */
  struct timeval time;  /* (read only, except for ADJ_SETOFFSET) */
  long tick;            /* (modified) usecs between clock ticks */
  long ppsfreq;         /* pps frequency (scaled ppm) (ro) */
  long jitter;          /* pps jitter (us) (ro) */
  int  shift;           /* interval duration (s) (shift) (ro) */
  long stabil;          /* pps stability (scaled ppm) (ro) */
  long jitcnt;          /* jitter limit exceeded (ro) */
  long calcnt;          /* calibration intervals (ro) */
  long errcnt;          /* calibration errors (ro) */
  long stbcnt;          /* stability limit exceeded (ro) */
  int  tai;             /* TAI offset (ro) */
  /* Reserved. The kernel copies the WHOLE struct; see the note above. */
  int  __pad[11];
};

struct ntptimeval {
  struct timeval time;  /* current time (ro) */
  long maxerror;        /* maximum error (us) (ro) */
  long esterror;        /* estimated error (us) (ro) */
  long tai;             /* TAI offset (ro) */
  long __glibc_reserved1;
  long __glibc_reserved2;
  long __glibc_reserved3;
  long __glibc_reserved4;
};

/* Mode codes (timex.mode) */
#define ADJ_OFFSET             0x0001  /* time offset */
#define ADJ_FREQUENCY          0x0002  /* frequency offset */
#define ADJ_MAXERROR           0x0004  /* maximum time error */
#define ADJ_ESTERROR           0x0008  /* estimated time error */
#define ADJ_STATUS             0x0010  /* clock status */
#define ADJ_TIMECONST          0x0020  /* pll time constant */
#define ADJ_TAI                0x0080  /* set TAI offset */
#define ADJ_SETOFFSET          0x0100  /* add 'time' to current time */
#define ADJ_MICRO              0x1000  /* select microsecond resolution */
#define ADJ_NANO               0x2000  /* select nanosecond resolution */
#define ADJ_TICK               0x4000  /* tick value */
#define ADJ_OFFSET_SINGLESHOT  0x8001  /* old-fashioned adjtime -- see above */
#define ADJ_OFFSET_SS_READ     0xa001  /* read-only adjtime */

/* The older spellings. Same values. */
#define MOD_OFFSET     ADJ_OFFSET
#define MOD_FREQUENCY  ADJ_FREQUENCY
#define MOD_MAXERROR   ADJ_MAXERROR
#define MOD_ESTERROR   ADJ_ESTERROR
#define MOD_STATUS     ADJ_STATUS
#define MOD_TIMECONST  ADJ_TIMECONST
#define MOD_CLKB       ADJ_TICK
#define MOD_CLKA       ADJ_OFFSET_SINGLESHOT
#define MOD_TAI        ADJ_TAI
#define MOD_MICRO      ADJ_MICRO
#define MOD_NANO       ADJ_NANO

/* Status codes (timex.status) */
#define STA_PLL        0x0001  /* enable PLL updates (rw) */
#define STA_PPSFREQ    0x0002  /* enable PPS freq discipline (rw) */
#define STA_PPSTIME    0x0004  /* enable PPS time discipline (rw) */
#define STA_FLL        0x0008  /* select frequency-lock mode (rw) */
#define STA_INS        0x0010  /* insert leap (rw) */
#define STA_DEL        0x0020  /* delete leap (rw) */
#define STA_UNSYNC     0x0040  /* clock unsynchronized (rw) */
#define STA_FREQHOLD   0x0080  /* hold frequency (rw) */
#define STA_PPSSIGNAL  0x0100  /* PPS signal present (ro) */
#define STA_PPSJITTER  0x0200  /* PPS signal jitter exceeded (ro) */
#define STA_PPSWANDER  0x0400  /* PPS signal wander exceeded (ro) */
#define STA_PPSERROR   0x0800  /* PPS signal calibration error (ro) */
#define STA_CLOCKERR   0x1000  /* clock hardware fault (ro) */
#define STA_NANO       0x2000  /* resolution (0 = us, 1 = ns) (ro) */
#define STA_MODE       0x4000  /* mode (0 = PLL, 1 = FLL) (ro) */
#define STA_CLK        0x8000  /* clock source (0 = A, 1 = B) (ro) */

#define STA_RONLY (STA_PPSSIGNAL | STA_PPSJITTER | STA_PPSWANDER \
    | STA_PPSERROR | STA_CLOCKERR | STA_NANO | STA_MODE | STA_CLK)

/* Clock states (adjtimex's RETURN value, not an error) */
#define TIME_OK     0  /* clock synchronized, no leap second */
#define TIME_INS    1  /* insert leap second */
#define TIME_DEL    2  /* delete leap second */
#define TIME_OOP    3  /* leap second in progress */
#define TIME_WAIT   4  /* leap second has occurred */
#define TIME_ERROR  5  /* clock not synchronized */
#define TIME_BAD    TIME_ERROR  /* bw compat */

/* Maximum time constant of the PLL. */
#define MAXTC  6

int adjtimex(struct timex *ntx);
int ntp_adjtime(struct timex *tntx);
int ntp_gettime(struct ntptimeval *ntv);

#endif
