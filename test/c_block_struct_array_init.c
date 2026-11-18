#include <stdio.h>
#include <stdint.h>
/* Block-scope struct arrays: an unsized outer dimension sized from the braces
   (LVGL lv_palette_lighten's static colors[][5] had one row and read black),
   and a partial initialiser zero-filling every element, not just [0].
   bug-c-a-block-scope-struct-array-with-an-unsized-outer-dimension-has-one-row
   bug-c-a-block-scope-struct-array-initialiser-zeroes-only-element-0 */
typedef struct { uint8_t b, g, r; } col_t;
typedef struct { int a; struct { int x, y; } in; } nest_t;
static col_t pick(int p, int l) {
  static const col_t colors[][3] = { {{1,2,3},{4,5,6},{7,8,9}}, {{21,22,23},{24,25,26},{27,28,29}}, {{31,32,33}} };
  return colors[p][l];
}
static int main1(void) {
  col_t a[][2] = { {{1,2,3},{4,5,6}}, {{7,8,9},{10,11,12}} };
  col_t e[][2] = { {1,2,3},{4,5,6},{7,8,9} };            /* 3 braced rows, each [0] set */
  col_t f[][2] = { 1,2,3, 4,5,6, 7,8,9 };               /* flat: 3 records = 2 rows */
  static nest_t n[][2] = { {{1,{2,3}},{4,{5,6}}}, {{7,{8,9}}} };
  static struct { int a; } s[][2] = { {{1},{2}}, {{3},{4}} };
  int i, j;
  printf("%d %d %d %d %d %d %d\n", (int)sizeof(a), (int)sizeof(e), (int)sizeof(f), f[1][0].r, (int)sizeof(n), (int)sizeof(s), pick(1, 2).r);
  for (i = 0; i < 3; i++) for (j = 0; j < 3; j++) printf("%d ", pick(i, j).b);
  for (i = 0; i < 2; i++) for (j = 0; j < 2; j++) printf("| %d %d %d %d %d ", a[i][j].r, e[i][j].r, n[i][j].a, n[i][j].in.y, s[i][j].a);
  printf("\n");
  return 0;
}

typedef struct { int a, b; } ip_t;
static void dirty(void) { volatile char junk[512]; int i; for (i = 0; i < 512; i++) junk[i] = 0x7f; }
static void show(void) {
  col_t x[4] = { {1,2,3} };
  ip_t y[4] = { {1,2} };
  ip_t z[2][2] = { {{1,2}}, {{3,4}} };
  col_t e[3][2] = { {1,2,3},{4,5,6},{7,8,9} };
  int i;
  for (i = 0; i < 4; i++) printf("%d,%d,%d/%d,%d ", x[i].b, x[i].r, y[i].a, y[i].b, ((ip_t *)z)[i].b);
  for (i = 0; i < 6; i++) printf("%d ", ((col_t *)e)[i].r);
  printf("\n");
}
int main(void) { main1(); dirty(); show(); return 0; }
