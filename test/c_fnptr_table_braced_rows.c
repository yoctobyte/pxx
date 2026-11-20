/* A function-pointer table initialised in braced rows, `{ {fa, fb}, {fb, fa} }`.
   Each inner brace was taken as one element and skipped, so the whole table
   was null slots. libX11's `static void (*SwapFunction[12][12])(...)` in
   PutImage.c is this shape: every XPutImage of a bitmap called through nil.
   bug-c-a-braced-row-in-a-function-pointer-table-initialiser-is-a-null-slot */
#include <stdio.h>
static void fa(int x) { printf("a%d ", x); }
static void fb(int x) { printf("b%d ", x); }
static void fc(int x) { printf("c%d ", x); }
typedef void (*FP)(int);
static void (* const (T2[2][3]))(int) = { {fa, fb, fc}, {fc, fb, fa} };
void (*G2[3][2])(int) = { {fa}, {fb, fc}, {fc} };        /* partial rows */
static FP D2[2][3] = { {[2] = fc}, {fa, [2] = fb} };      /* designators in a row */
static FP M2[2][2] = { {fa, fb}, fc, fa };                /* braced, then flat */
static FP U2[][2] = { {fa}, {fb} };                      /* unbounded: whole rows */
static void (*T3[2][2][2])(int) = { { {fa, fb}, {fb, fc} }, { {fc, fa}, {fa, fa} } };
static void call(FP f, int n) { if (f) f(n); else printf("0 "); }
int main(void)
{
  int i, j, k;
  for (i = 0; i < 2; i++) for (j = 0; j < 3; j++) call(T2[i][j], i * 3 + j);
  printf("\n");
  for (i = 0; i < 3; i++) for (j = 0; j < 2; j++) call(G2[i][j], i * 2 + j);
  printf("\n");
  for (i = 0; i < 2; i++) for (j = 0; j < 3; j++) call(D2[i][j], i * 3 + j);
  printf("\n");
  for (i = 0; i < 2; i++) for (j = 0; j < 2; j++) call(M2[i][j], i * 2 + j);
  printf("\n");
  for (i = 0; i < 2; i++) for (j = 0; j < 2; j++) for (k = 0; k < 2; k++) call(T3[i][j][k], i * 4 + j * 2 + k);
  printf("\n");
  for (i = 0; i < 2; i++) for (j = 0; j < 2; j++) call(U2[i][j], i * 2 + j);
  printf("\n%d %d %d %d\n", (int)sizeof T2, (int)sizeof G2, (int)sizeof T3, (int)sizeof U2);
  return 0;
}
