/* Regression (bug-c-sizeof-a-file-scope-double-array-answers-one-element): a
 * file-scope FLOAT/DOUBLE array whose length comes from its INITIALIZER
 * (`double a[] = {...}`, no explicit [N]) was sized to ONE element. The length
 * inference only ran for TypeIsOrdinal base types, so a float array missed
 * every arm and fell through to `arrLen := 1`.
 *
 * Three symptoms, all silent: sizeof(a) answered one element (so the universal
 * sizeof(a)/sizeof(a[0]) idiom yielded 1 and every loop ran one iteration),
 * only element [0] of the initializer was stored, and the array overlapped the
 * next global — a[1] read the neighbour's storage and a[k] wrote over it.
 *
 * cfloat_global_array_init_b197.c is the sibling and covers only EXPLICIT-size
 * forms, so it never saw this. Returns 42. */
#include <stdio.h>

static double A[] = {1.5, 2.5, 3.5, 4.5, 5.5};   /* implicit 5 */
static double Z[] = {9.5, 8.5, 7.5};             /* the neighbour A used to eat */
static float  F[] = {10.0f, 20.0f, 30.0f, 40.0f};/* implicit 4, float */
static double I[] = {7, 8, 9};                   /* int elements -> double */
static double D[] = {1.0, [3] = 8.0};            /* designator sizes it to 4 */
static int    G = 77;                            /* must survive A/Z writes */

int main(void) {
  int i, n;
  double s;

  /* the idiom itself — this is what silently answered 1 */
  if ((int)(sizeof(A) / sizeof(A[0])) != 5) { printf("A n=%d\n", (int)(sizeof(A)/sizeof(A[0]))); return 1; }
  if ((int)(sizeof(F) / sizeof(F[0])) != 4) return 2;
  if ((int)(sizeof(I) / sizeof(I[0])) != 3) return 3;
  if ((int)(sizeof(D) / sizeof(D[0])) != 4) return 4;
  if ((int)sizeof(A) != 40 || (int)sizeof(F) != 16) return 5;

  /* every element stored, not just [0] */
  n = (int)(sizeof(A) / sizeof(A[0]));
  s = 0.0;
  for (i = 0; i < n; i++) s += A[i];
  if (s < 17.4 || s > 17.6) { printf("sumA=%f\n", s); return 6; }   /* 17.5 */

  s = 0.0;
  for (i = 0; i < (int)(sizeof(F)/sizeof(F[0])); i++) s += F[i];
  if (s < 99.9 || s > 100.1) return 7;                              /* 100.0 */

  if (I[0] != 7.0 || I[1] != 8.0 || I[2] != 9.0) return 8;
  if (D[0] != 1.0 || D[1] != 0.0 || D[2] != 0.0 || D[3] != 8.0) return 9;

  /* no overlap: A must not alias Z, and writing A's tail must not touch them */
  if (Z[0] != 9.5 || Z[1] != 8.5 || Z[2] != 7.5) { printf("Z clobbered\n"); return 10; }
  A[4] = 99.5;
  if (Z[0] != 9.5 || Z[1] != 8.5 || Z[2] != 7.5) return 11;
  if (G != 77) return 12;
  if (A[4] != 99.5 || A[0] != 1.5) return 13;

  return 42;
}
