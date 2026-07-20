/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_INTTYPES_H
#define PXX_CRTL_INTTYPES_H 1

/* C99 <inttypes.h> — fixed-width integer format macros, imaxdiv, and the
   intmax_t string conversions.

   Every macro below is derived from OUR <stdint.h>, not from glibc's — the two
   disagree and copying glibc's table would be silently wrong. In particular:
     intmax_t     is long long here  -> the MAX group is "ll*", not "l*"
     int_fast16_t is long here       -> FAST16/FAST32 are "l*", not plain
     intptr_t     is long            -> the PTR group is "l*"
   A mismatch does not warn at the call site (these are varargs) — it reads the
   wrong number of bytes off the stack and prints garbage, so these must be
   re-derived, not assumed, if stdint.h ever changes or a 32-bit target lands.

   Completeness matters more than it looks. These macros exist so portable C can
   print and SCAN fixed-width types, and a missing one is not an error at its
   definition: it is an undefined identifier inside a string-concatenation
   context, which surfaces as a confusing syntax error some distance from the
   cause. This header previously had the common PRI subset and no SCN macros at
   all, so every `scanf("%" SCNd64, &v)` failed that way. */

#include <stdint.h>

/* ---- fprintf: signed decimal ---- */
#define PRId8         "d"
#define PRId16        "d"
#define PRId32        "d"
#define PRId64        "lld"
#define PRIdLEAST8    "d"
#define PRIdLEAST16   "d"
#define PRIdLEAST32   "d"
#define PRIdLEAST64   "lld"
#define PRIdFAST8     "d"
#define PRIdFAST16    "ld"
#define PRIdFAST32    "ld"
#define PRIdFAST64    "lld"

#define PRIi8         "i"
#define PRIi16        "i"
#define PRIi32        "i"
#define PRIi64        "lli"
#define PRIiLEAST8    "i"
#define PRIiLEAST16   "i"
#define PRIiLEAST32   "i"
#define PRIiLEAST64   "lli"
#define PRIiFAST8     "i"
#define PRIiFAST16    "li"
#define PRIiFAST32    "li"
#define PRIiFAST64    "lli"

/* ---- fprintf: unsigned decimal / octal / hex ---- */
#define PRIu8         "u"
#define PRIu16        "u"
#define PRIu32        "u"
#define PRIu64        "llu"
#define PRIuLEAST8    "u"
#define PRIuLEAST16   "u"
#define PRIuLEAST32   "u"
#define PRIuLEAST64   "llu"
#define PRIuFAST8     "u"
#define PRIuFAST16    "lu"
#define PRIuFAST32    "lu"
#define PRIuFAST64    "llu"

#define PRIo8         "o"
#define PRIo16        "o"
#define PRIo32        "o"
#define PRIo64        "llo"
#define PRIoLEAST8    "o"
#define PRIoLEAST16   "o"
#define PRIoLEAST32   "o"
#define PRIoLEAST64   "llo"
#define PRIoFAST8     "o"
#define PRIoFAST16    "lo"
#define PRIoFAST32    "lo"
#define PRIoFAST64    "llo"

#define PRIx8         "x"
#define PRIx16        "x"
#define PRIx32        "x"
#define PRIx64        "llx"
#define PRIxLEAST8    "x"
#define PRIxLEAST16   "x"
#define PRIxLEAST32   "x"
#define PRIxLEAST64   "llx"
#define PRIxFAST8     "x"
#define PRIxFAST16    "lx"
#define PRIxFAST32    "lx"
#define PRIxFAST64    "llx"

#define PRIX8         "X"
#define PRIX16        "X"
#define PRIX32        "X"
#define PRIX64        "llX"
#define PRIXLEAST8    "X"
#define PRIXLEAST16   "X"
#define PRIXLEAST32   "X"
#define PRIXLEAST64   "llX"
#define PRIXFAST8     "X"
#define PRIXFAST16    "lX"
#define PRIXFAST32    "lX"
#define PRIXFAST64    "llX"

/* ---- fscanf: signed ----
   The 8/16-bit SCN macros carry a length modifier where the PRI ones do not.
   Printing promotes a narrow type to int, so "%d" is correct; scanning writes
   THROUGH a pointer, so the width must be stated or scanf overwrites adjacent
   memory. That failure is silent corruption, not a diagnostic. */
#define SCNd8         "hhd"
#define SCNd16        "hd"
#define SCNd32        "d"
#define SCNd64        "lld"
#define SCNdLEAST8    "hhd"
#define SCNdLEAST16   "hd"
#define SCNdLEAST32   "d"
#define SCNdLEAST64   "lld"
#define SCNdFAST8     "hhd"
#define SCNdFAST16    "ld"
#define SCNdFAST32    "ld"
#define SCNdFAST64    "lld"

#define SCNi8         "hhi"
#define SCNi16        "hi"
#define SCNi32        "i"
#define SCNi64        "lli"
#define SCNiLEAST8    "hhi"
#define SCNiLEAST16   "hi"
#define SCNiLEAST32   "i"
#define SCNiLEAST64   "lli"
#define SCNiFAST8     "hhi"
#define SCNiFAST16    "li"
#define SCNiFAST32    "li"
#define SCNiFAST64    "lli"

/* ---- fscanf: unsigned / octal / hex ---- */
#define SCNu8         "hhu"
#define SCNu16        "hu"
#define SCNu32        "u"
#define SCNu64        "llu"
#define SCNuLEAST8    "hhu"
#define SCNuLEAST16   "hu"
#define SCNuLEAST32   "u"
#define SCNuLEAST64   "llu"
#define SCNuFAST8     "hhu"
#define SCNuFAST16    "lu"
#define SCNuFAST32    "lu"
#define SCNuFAST64    "llu"

#define SCNo8         "hho"
#define SCNo16        "ho"
#define SCNo32        "o"
#define SCNo64        "llo"
#define SCNoLEAST8    "hho"
#define SCNoLEAST16   "ho"
#define SCNoLEAST32   "o"
#define SCNoLEAST64   "llo"
#define SCNoFAST8     "hho"
#define SCNoFAST16    "lo"
#define SCNoFAST32    "lo"
#define SCNoFAST64    "llo"

#define SCNx8         "hhx"
#define SCNx16        "hx"
#define SCNx32        "x"
#define SCNx64        "llx"
#define SCNxLEAST8    "hhx"
#define SCNxLEAST16   "hx"
#define SCNxLEAST32   "x"
#define SCNxLEAST64   "llx"
#define SCNxFAST8     "hhx"
#define SCNxFAST16    "lx"
#define SCNxFAST32    "lx"
#define SCNxFAST64    "llx"

/* ---- pointer-width (LP64: intptr_t is long) ---- */
#define PRIdPTR       "ld"
#define PRIiPTR       "li"
#define PRIuPTR       "lu"
#define PRIoPTR       "lo"
#define PRIxPTR       "lx"
#define PRIXPTR       "lX"

#define SCNdPTR       "ld"
#define SCNiPTR       "li"
#define SCNuPTR       "lu"
#define SCNoPTR       "lo"
#define SCNxPTR       "lx"

/* ---- greatest-width (intmax_t is long long in our stdint.h) ---- */
#define PRIdMAX       "lld"
#define PRIiMAX       "lli"
#define PRIuMAX       "llu"
#define PRIoMAX       "llo"
#define PRIxMAX       "llx"
#define PRIXMAX       "llX"

#define SCNdMAX       "lld"
#define SCNiMAX       "lli"
#define SCNuMAX       "llu"
#define SCNoMAX       "llo"
#define SCNxMAX       "llx"

/* intmax_t / uintmax_t live in <stdint.h> (C99 7.18.1.5), included above. */

typedef struct {
  intmax_t quot;
  intmax_t rem;
} imaxdiv_t;

extern intmax_t  imaxabs(intmax_t j);
extern imaxdiv_t imaxdiv(intmax_t numer, intmax_t denom);

extern intmax_t  strtoimax(const char *nptr, char **endptr, int base);
extern uintmax_t strtoumax(const char *nptr, char **endptr, int base);

#endif
