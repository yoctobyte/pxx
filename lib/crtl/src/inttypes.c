/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: inttypes — the greatest-width conversions <inttypes.h> declares.
 *
 * These lived in stdlib.c until 2026-08-10, which made them unreachable for a
 * program that includes only <inttypes.h>: the crtl auto-pull looks for the
 * header's SIBLING impl (`inttypes.h` -> `src/inttypes.c`), found no such file,
 * and correctly concluded "header-only module" — so imaxdiv/strtoimax were
 * declared, never emitted, and the call jumped to garbage with no diagnostic
 * (bug-c-crtl-auto-pull-depends-on-the-pascal-preludes-unit-count). The rule
 * the auto-pull encodes is that a header's functions live in its sibling .c;
 * a header that breaks it is silently broken.
 *
 * LP64, so intmax_t is long and these are one-line forwards over <stdlib.h>'s
 * strtol/strtoul. They exist as real symbols rather than macros because
 * <inttypes.h> declares them as functions and portable C takes their address.
 */

#include <inttypes.h>
#include <stdlib.h>

intmax_t imaxabs(intmax_t j) { return j < 0 ? -j : j; }

imaxdiv_t imaxdiv(intmax_t numer, intmax_t denom) {
  imaxdiv_t r;
  r.quot = numer / denom;
  r.rem  = numer - r.quot * denom;
  return r;
}

intmax_t strtoimax(const char *nptr, char **endptr, int base) {
  return (intmax_t)strtol(nptr, endptr, base);
}

uintmax_t strtoumax(const char *nptr, char **endptr, int base) {
  return (uintmax_t)strtoul(nptr, endptr, base);
}
