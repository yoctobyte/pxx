/* `__has_include` (C23 6.10.1), and the reason it is a bug rather than a
 * missing feature.
 *
 * pxx did not define it, so vendored pdfgen skipped the whole probe block that
 * pulls in <endian.h>:
 *
 *     #ifdef __has_include            <- false, so the block never ran
 *     #if __has_include(<endian.h>)
 *     #include <endian.h>
 *     #endif
 *     #endif
 *
 * and its fallback below then reached an `#elif` whose right arm compares
 * __BYTE_ORDER against __BIG_ENDIAN -- two macros only <endian.h> defines.
 * Undefined identifiers are 0 in #if, so that is `0 == 0`, i.e. TRUE, and
 * pdfgen selected BIG endian on x86-64. ntoh32 became the identity, every
 * 32-bit PNG header field came back byte-swapped, and PNG embedding failed
 * with "PNG chunk exceeds file: 218103808 vs 105" -- 0x0D000000, the IHDR
 * length 13 with its bytes reversed.
 *
 * Nothing about that is loud: it compiles, links, runs, and returns a wrong
 * number. The endian block below is pdfgen's, verbatim, because the operator
 * working in isolation is not the property that was missing -- this exact
 * chain reaching the right arm is.
 *
 * Note the operator is only valid INSIDE a preprocessing directive; gcc
 * rejects `__has_include(...)` in ordinary code, and so does pxx, so every
 * use here is in a directive and the results are carried out in flags. */

#include <stdio.h>

/* 1. visible to #ifdef / defined(), which is what pdfgen tests */
#ifdef __has_include
static const int seen_ifdef = 1;
#else
static const int seen_ifdef = 0;
#endif
#if defined(__has_include)
static const int seen_defined = 1;
#else
static const int seen_defined = 0;
#endif

/* 2. a header that exists is 1, one that does not is 0 -- and the missing one
      must NOT be an error, which is the whole point of asking */
#if __has_include(<stdio.h>)
static const int have_stdio = 1;
#else
static const int have_stdio = 0;
#endif
#if __has_include(<no_such_header_xyz_pxx.h>)
static const int have_bogus = 1;
#else
static const int have_bogus = 0;
#endif

/* 3. the quoted form resolves relative to the including file */
#if __has_include("chas_include_rel.h")
static const int have_rel = 1;
#else
static const int have_rel = 0;
#endif

/* 4. pdfgen's chain, verbatim. The assertion is the SELECTION, not the
      operator. */
#ifdef __has_include
#if __has_include(<endian.h>)
#include <endian.h>
#elif __has_include(<machine/endian.h>)
#include <machine/endian.h>
#elif __has_include(<sys/param.h>)
#include <sys/param.h>
#endif
#endif

#if !defined(__LITTLE_ENDIAN__) && !defined(__BIG_ENDIAN__)
#ifndef __BYTE_ORDER__
#define __LITTLE_ENDIAN__
#elif __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__ || __BYTE_ORDER == __BIG_ENDIAN
#define __BIG_ENDIAN__
#else
#define __LITTLE_ENDIAN__
#endif
#endif

int main(void) {
  printf("ifdef %d\n", seen_ifdef);
  printf("defined %d\n", seen_defined);
  printf("stdio %d\n", have_stdio);
  printf("bogus %d\n", have_bogus);
  printf("rel %d\n", have_rel);
#if defined(__LITTLE_ENDIAN__)
  printf("pdfgen little\n");
#elif defined(__BIG_ENDIAN__)
  printf("pdfgen BIG\n");
#else
  printf("pdfgen none\n");
#endif
  return 0;
}
