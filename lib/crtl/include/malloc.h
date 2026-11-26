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

/* The ACTUAL usable bytes of a block, which is what glibc answers and is more
   than the caller asked for whenever the allocator rounded up -- and PXXAlloc
   rounds every allocation up to 8. So this is a real number read from the
   block's own header, NOT the requested size: returning the request would be
   wrong for every size that is not already a multiple of 8, and wrong in the
   silent direction, because a caller using it for memory accounting would
   under-report a total rather than crash.

   quickjs-ng is what brought this in (cutils.h js__malloc_usable_size, reached
   because we define __linux__), and it uses it for exactly that accounting.
   Its own portable #else arm returns 0 on platforms that cannot report a size,
   so 0 -- which this returns for NULL or an implausible header -- is a value
   that library is already built to survive.
   bug-c-malloc-usable-size-is-undeclared-so-quickjs-cannot-compile */
size_t malloc_usable_size(void *ptr);
void *memalign(size_t align, size_t size);

/* mallinfo2 / mallinfo: glibc's layout and field names, crtl's numbers. The
   allocator keeps exact counts (GetFPCHeapStatus): arena is the bytes it has
   mapped, uordblks the bytes handed out and live, fordblks the mapped
   remainder. It has no separate mmap tier, no fastbins and no top chunk to
   trim, so hblks, hblkhd, smblks, fsmblks and keepcost are 0, which is true.
   ordblks (free chunks) is not counted: 0. usmblks is 0 as in glibc.
   mallinfo is the same with int fields, wrapped as glibc wraps them past
   2 GiB. e2fsck -t prints these ("Memory used: ..."). */
struct mallinfo2 {
  size_t arena, ordblks, smblks, hblks, hblkhd, usmblks, fsmblks, uordblks, fordblks, keepcost;
};
struct mallinfo {
  int arena, ordblks, smblks, hblks, hblkhd, usmblks, fsmblks, uordblks, fordblks, keepcost;
};
struct mallinfo2 mallinfo2(void);
struct mallinfo mallinfo(void);

#endif
