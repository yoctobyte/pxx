/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <stdio_ext.h> -- the Solaris/glibc questions about a stream's
 * state. Only the ones a program here asks: __fpending (util-linux's
 * close_stdout, include/closestream.h, checks that nothing is left unwritten
 * before it trusts ferror), __fsetlocking and _flushlbf. Not __fpurge: what
 * it drops is glibc's read-ahead, which crtl's streams do not have in the
 * same amounts, so its answer could only be imitated.
 *
 * crtl's output is UNBUFFERED (src/stdio.c: every write reaches the fd or the
 * memory buffer at once), so __fpending is always 0 and _flushlbf has nothing
 * to flush: the answers glibc gives right after an fflush, which is the state
 * crtl is always in. There are no stream locks, so __fsetlocking only
 * remembers what it was told.
 */
#ifndef _CRTL_STDIO_EXT_H
#define _CRTL_STDIO_EXT_H
#include <stdio.h>

enum {
  FSETLOCKING_QUERY = 0,
  FSETLOCKING_INTERNAL,
  FSETLOCKING_BYCALLER
};
#define FSETLOCKING_QUERY    FSETLOCKING_QUERY
#define FSETLOCKING_INTERNAL FSETLOCKING_INTERNAL
#define FSETLOCKING_BYCALLER FSETLOCKING_BYCALLER

size_t __fpending(FILE *fp);
int __fsetlocking(FILE *fp, int type);
void _flushlbf(void);

#endif
