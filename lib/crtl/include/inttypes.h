/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_INTTYPES_H
#define PXX_CRTL_INTTYPES_H 1

/* Fixed-width integer format macros (the subset sqlite/lua reference). LP64:
   int64_t = long long, so the 64-bit conversions use the "ll" length modifier. */

#include <stdint.h>

#define PRId8   "d"
#define PRId16  "d"
#define PRId32  "d"
#define PRId64  "lld"
#define PRIi64  "lli"
#define PRIu8   "u"
#define PRIu16  "u"
#define PRIu32  "u"
#define PRIu64  "llu"
#define PRIx64  "llx"
#define PRIX64  "llX"
#define PRIo64  "llo"

#define PRIdPTR "ld"
#define PRIuPTR "lu"
#define PRIxPTR "lx"

typedef long long          intmax_t;
typedef unsigned long long uintmax_t;

extern intmax_t  strtoimax(const char *nptr, char **endptr, int base);
extern uintmax_t strtoumax(const char *nptr, char **endptr, int base);

#endif
