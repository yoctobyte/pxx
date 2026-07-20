/* SPDX-License-Identifier: Zlib */
/* <inttypes.h> completeness: the PRI/SCN macros must exist AND carry the length
   modifier that matches our own <stdint.h> (see the header's note — glibc's
   table disagrees and copying it would be silently wrong).

   Deliberately printf-free: it checks the macro STRINGS with strcmp and exits
   42, the convention the other crtl_*.c tests use. That is not squeamishness —
   a wrong length modifier is a varargs bug, so a printf-based check would be
   testing the bug with the bug. Comparing the strings tests the actual claim.

   Returns 42 on success, 1..N identifying the first failing group.

   NOTE: gcc does NOT return 42 here, and must not be "fixed" to. glibc's
   int64_t is long and its intmax_t is long, where ours are long long, so the
   64-bit and MAX groups legitimately differ. This test asserts OUR ABI. If you
   ever port it to a gcc oracle, only the 8/16/32-bit and LEAST groups are
   common ground. */

#include <inttypes.h>
#include <string.h>

int main(void) {
  /* 64-bit: int64_t is long long here */
  if (strcmp(PRId64, "lld") || strcmp(PRIu64, "llu") ||
      strcmp(PRIx64, "llx") || strcmp(PRIX64, "llX") ||
      strcmp(PRIo64, "llo") || strcmp(PRIi64, "lli")) return 1;
  if (strcmp(SCNd64, "lld") || strcmp(SCNu64, "llu") || strcmp(SCNx64, "llx")) return 2;

  /* 32/16/8-bit printing promotes to int; scanning must state the width */
  if (strcmp(PRId32, "d") || strcmp(PRIu16, "u") || strcmp(PRIx8, "x")) return 3;
  if (strcmp(SCNd8, "hhd") || strcmp(SCNd16, "hd") || strcmp(SCNd32, "d")) return 4;
  if (strcmp(SCNu8, "hhu") || strcmp(SCNx16, "hx")) return 5;

  /* int_least32_t is int; int_least64_t is long long */
  if (strcmp(PRIdLEAST32, "d") || strcmp(PRIdLEAST64, "lld")) return 6;
  if (strcmp(SCNdLEAST16, "hd") || strcmp(SCNdLEAST64, "lld")) return 7;

  /* int_fast16_t / int_fast32_t are LONG in our stdint.h, not int */
  if (strcmp(PRIdFAST16, "ld") || strcmp(PRIdFAST32, "ld") ||
      strcmp(PRIuFAST32, "lu")) return 8;
  if (strcmp(SCNdFAST16, "ld") || strcmp(SCNdFAST32, "ld")) return 9;
  if (strcmp(PRIdFAST8, "d") || strcmp(SCNdFAST8, "hhd")) return 10;
  if (strcmp(PRIdFAST64, "lld")) return 11;

  /* intptr_t is long */
  if (strcmp(PRIdPTR, "ld") || strcmp(PRIuPTR, "lu") || strcmp(PRIxPTR, "lx") ||
      strcmp(PRIXPTR, "lX") || strcmp(PRIiPTR, "li") || strcmp(PRIoPTR, "lo")) return 12;
  if (strcmp(SCNdPTR, "ld") || strcmp(SCNxPTR, "lx")) return 13;

  /* intmax_t is LONG LONG in our stdint.h — glibc's is long, so this group is
     exactly where a copied table would have been wrong */
  if (strcmp(PRIdMAX, "lld") || strcmp(PRIuMAX, "llu") || strcmp(PRIxMAX, "llx") ||
      strcmp(PRIXMAX, "llX") || strcmp(PRIiMAX, "lli") || strcmp(PRIoMAX, "llo")) return 14;
  if (strcmp(SCNdMAX, "lld") || strcmp(SCNuMAX, "llu")) return 15;

  /* the declared-and-now-implemented functions */
  if (imaxabs((intmax_t)-99) != 99) return 16;
  if (imaxabs((intmax_t)99) != 99) return 17;
  {
    imaxdiv_t q = imaxdiv(17, 5);
    if (q.quot != 3 || q.rem != 2) return 18;
    q = imaxdiv(-17, 5);
    /* C99: truncation toward zero, so -3 remainder -2 */
    if (q.quot != -3 || q.rem != -2) return 19;
  }
  if (strtoimax("-9911", 0, 10) != -9911) return 20;
  if (strtoumax("ff", 0, 16) != 255u) return 21;
  {
    char *end = 0;
    if (strtoimax("42abc", &end, 10) != 42) return 22;
    if (!end || *end != 'a') return 23;
  }
  return 42;
}
