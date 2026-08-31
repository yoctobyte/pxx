/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: allocator tuning. The allocator itself is in stdlib.c; this file
 * exists because <malloc.h> declares mallopt, and a header whose function has
 * no definition in this tree is worse than no header at all -- the program
 * links the SYSTEM libc's copy instead, silently, against a different heap.
 * tools/crtl_reachability.py exists to catch exactly that.
 */
#include <malloc.h>

int mallopt(int param, int value)
{
  (void)param;
  (void)value;
  return 0;   /* not set -- see the note in <malloc.h> */
}
