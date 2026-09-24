/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <utime.h> -- POSIX utime() and struct utimbuf.
 *
 * Obsolescent in POSIX and still everywhere: sqlite's shell.c includes it for
 * `.archive`, and without this header the include fell through to the host's
 * /usr/include/utime.h, which does not parse outside glibc (`__BEGIN_DECLS`).
 * Layout is glibc's: two time_t, seconds only.
 */
#ifndef _CRTL_UTIME_H
#define _CRTL_UTIME_H

#include <sys/types.h>
#include <time.h>

struct utimbuf {
  time_t actime;    /* access time */
  time_t modtime;   /* modification time */
};

int utime(const char *file, const struct utimbuf *times);

#endif
