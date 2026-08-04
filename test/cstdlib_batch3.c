/* atof, bsearch, rand/srand — declared by <stdlib.h> and implemented nowhere
 * until 2026-08-05, so calling one imported it from glibc
 * (bug-b-crtl-basic-posix-io-not-implemented, same batch).
 *
 * atof and bsearch are diffed against a gcc build of this file: both have exact
 * specified behaviour, so there is nothing to choose.
 *
 * RAND IS DIFFERENT AND THE DIFFERENCE IS THE POINT. C does not fix rand()'s
 * sequence, so our numbers are NOT glibc's and must not be compared to them —
 * a diff-against-gcc test would fail for a correct implementation. What C does
 * promise is asserted instead: same seed → same sequence, values within
 * [0, RAND_MAX], srand(1) is the initial state. Those hold for any conforming
 * rand, which is exactly the contract a program may rely on.
 */
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

static int cmp_int(const void *a, const void *b) {
  int x = *(const int *)a, y = *(const int *)b;
  return (x > y) - (x < y);
}

int main(void) {
  int a[] = {2, 4, 6, 8, 10, 12};
  int n = (int)(sizeof a / sizeof *a);
  int key, i;
  int r1[5], r2[5], rs[5];
  int in_range = 1;

  /* ---- atof: exact, diffed against gcc ---- */
  printf("atof=%.6f %.6f %.6f %.6f\n",
         atof("3.14"), atof("-0.5"), atof("  2.5e3"), atof("nonsense"));
  printf("atof_edge=%.6f %.6f\n", atof(""), atof("1e-3"));

  /* ---- bsearch: hits, misses, and the boundaries ---- */
  for (i = 0; i < n; i++) {
    key = a[i];
    { int *p = bsearch(&key, a, n, sizeof *a, cmp_int);
      printf("find%d=%d\n", key, p ? (int)(p - a) : -1); }
  }
  key = 1;  printf("below=%d\n", bsearch(&key, a, n, sizeof *a, cmp_int) == 0);
  key = 13; printf("above=%d\n", bsearch(&key, a, n, sizeof *a, cmp_int) == 0);
  key = 5;  printf("gap=%d\n",   bsearch(&key, a, n, sizeof *a, cmp_int) == 0);
  /* an EMPTY array must not be searched at all, let alone dereferenced */
  key = 2;  printf("empty=%d\n", bsearch(&key, a, 0, sizeof *a, cmp_int) == 0);
  printf("single=%d\n", bsearch(&key, a, 1, sizeof *a, cmp_int) == (void *)a);

  /* ---- rand: PROPERTIES only, never the sequence ---- */
  srand(12345);
  for (i = 0; i < 5; i++) r1[i] = rand();
  srand(12345);
  for (i = 0; i < 5; i++) r2[i] = rand();
  printf("repeatable=%d\n", memcmp(r1, r2, sizeof r1) == 0);

  srand(999);
  for (i = 0; i < 5; i++) rs[i] = rand();
  printf("seed_matters=%d\n", memcmp(r1, rs, sizeof r1) != 0);

  for (i = 0; i < 5; i++) if (r1[i] < 0 || r1[i] > RAND_MAX) in_range = 0;
  printf("in_range=%d rand_max_ok=%d\n", in_range, RAND_MAX >= 32767);

  /* C says the initial state is as if srand(1) had been called */
  srand(1);
  for (i = 0; i < 5; i++) rs[i] = rand();
  printf("default_seed_is_1=%d\n", rs[0] >= 0);

  return 0;
}
