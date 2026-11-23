/* `!(x && y)`, `!(x || y)` and a `for` test of `x && y` (built as
 * `if (cond == 0) break`) branch on x and y directly instead of storing the
 * `&&` in a temp. Paths and side-effect order against gcc.
 * feature-c-toybox-size-gap-literal-headers-call-realign-no-regalloc */
#include <stdio.h>
static int trace[64], nt;
static int t(int id, int v) { if (nt < 64) trace[nt++] = id; return v; }
int main(void) {
  int hits = 0, i, j, k;
  for (i = 0; i < 4; i++)
    for (j = 0; j < 4; j++) {
      if (!(t(1, i & 1) && t(2, j & 1))) hits += 1;
      if (!(t(3, i & 2) || t(4, j & 2))) hits += 10;
      if (!(!(i < j) && (i != 2 || j == 3))) hits += 100;
      else if (!((i == j) || (i + j == 3 && j > 0))) hits += 1000;
    }
  printf("hits %d trace %d", hits, nt);
  for (k = 0; k < nt && k < 20; k++) printf(" %d", trace[k]);
  printf("\n");
  int s = 0;
  for (i = 0; i < 10 && s < 20; i++) s += i;
  printf("for-and %d %d\n", i, s);
  s = 0;
  for (i = 0; i < 3 || s < 30; i++) { if (i == 7) break; if (i == 1) continue; s += i * 5; }
  printf("for-or %d %d\n", i, s);
  nt = 0; s = 0;
  for (i = 0; t(5, i < 5) && t(6, i != 3); i++) s++;
  printf("for-side %d %d %d\n", i, s, nt);
  i = 0;
  while (!(i > 6 || i * i > 20)) i++;
  printf("while-not-or %d\n", i);
  i = 0;
  do i++; while (!(i >= 3 && i % 2 == 0));
  printf("do-not-and %d\n", i);
  return 0;
}
