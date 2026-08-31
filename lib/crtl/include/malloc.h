/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <malloc.h> -- the GNU allocator-tuning header.
 *
 * The malloc family itself lives in <stdlib.h> and is pulled in from there,
 * exactly as glibc's own <malloc.h> does. What is HERE is the tuning knob:
 * mallopt and the M_* parameter numbers.
 *
 * The M_* values are glibc's, deliberately. They are negative and otherwise
 * arbitrary, and real code passes them straight through -- so a program that
 * compiled against the host header and one that compiled against this one must
 * hand the same integers to the same function, or the two builds diverge in a
 * way nothing reports.
 */
#ifndef _CRTL_MALLOC_H
#define _CRTL_MALLOC_H

#include <stdlib.h>

#define M_TRIM_THRESHOLD  -1
#define M_TOP_PAD         -2
#define M_MMAP_THRESHOLD  -3
#define M_MMAP_MAX        -4
#define M_CHECK_ACTION    -5
#define M_PERTURB         -6
#define M_ARENA_TEST      -7
#define M_ARENA_MAX       -8

/* Returns 0 -- "the parameter was not set" -- ALWAYS, and that is the point.
   crtl's allocator has no trim threshold, no mmap threshold and no top pad to
   set, so returning glibc's success value would claim a tuning that did not
   happen. Every caller measured in the corpus (busybox's appletlib.c is the
   one that brought this header into existence) ignores the result; a caller
   that checks it gets a truthful no. */
int mallopt(int param, int value);

#endif
