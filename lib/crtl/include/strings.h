/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_STRINGS_H
#define PXX_CRTL_STRINGS_H 1

/* The BSD string surface (POSIX <strings.h>, distinct from <string.h>).
 *
 * This header did not exist, so `#include <strings.h>` silently resolved from
 * the HOST's /usr/include — the compiler warns that ABI and macro mismatches
 * "may silently misbehave", and it names M_SQRT2 as the example, which turned
 * out to be a real silent-value bug in the very same build
 * (bug-b-crtl-math-constants-missing-silently-zero). Reaching outside pxx's own
 * headers also makes the build depend on the box it runs on.
 *
 * Defined as static functions rather than extern declarations, deliberately.
 * An extern `bcmp` bound by NAME to the Pascal routine `BCmp`, which takes two
 * parameters where C passes three, and the compiler warned that "the argument
 * list will not arrive as written" — a bcmp that loses its length can report
 * unequal buffers as equal. A local definition has no name to collide with and
 * cannot be bound to the wrong arity.
 *
 * All of these are thin spellings of <string.h> primitives, which is what they
 * are in every libc. Note bcopy's argument order is REVERSED relative to
 * memmove — that is the historical BSD signature, not a slip. */

#include <stddef.h>
#include <string.h>
#include <ctype.h>

/* Byte comparison: 0 when the first n bytes match, nonzero otherwise. Unlike
   memcmp the magnitude carries no ordering meaning. */
static int bcmp(const void *s1, const void *s2, size_t n) {
  return memcmp(s1, s2, n) != 0;
}

/* NOTE the argument order: source first, unlike memmove. Overlap is allowed. */
static void bcopy(const void *src, void *dest, size_t n) {
  memmove(dest, src, n);
}

static void bzero(void *s, size_t n) {
  memset(s, 0, n);
}

static char *index(const char *s, int c) {
  return strchr(s, c);
}

static char *rindex(const char *s, int c) {
  return strrchr(s, c);
}

/* Position of the least significant set bit, 1-based; 0 when i is 0. */
static int ffs(int i) {
  int n;
  if (i == 0)
    return 0;
  n = 1;
  while ((i & 1) == 0) {
    i = (int)((unsigned int)i >> 1);
    n = n + 1;
  }
  return n;
}

static int strcasecmp(const char *a, const char *b) {
  int ca, cb;
  for (;;) {
    ca = tolower((unsigned char)*a);
    cb = tolower((unsigned char)*b);
    if (ca != cb)
      return ca - cb;
    if (ca == 0)
      return 0;
    a++;
    b++;
  }
}

static int strncasecmp(const char *a, const char *b, size_t n) {
  int ca, cb;
  size_t i;
  for (i = 0; i < n; i++) {
    ca = tolower((unsigned char)a[i]);
    cb = tolower((unsigned char)b[i]);
    if (ca != cb)
      return ca - cb;
    if (ca == 0)
      return 0;
  }
  return 0;
}

#endif /* PXX_CRTL_STRINGS_H */
