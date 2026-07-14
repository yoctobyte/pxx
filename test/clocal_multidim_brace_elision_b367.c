/* LOCAL multidim brace init: a nested brace group fills exactly ONE
   sub-aggregate and its tail is zeroed (C99 6.7.8p21). The local flattening
   pre-scan concatenated the rows, so {{1},{2}} put 2 in row 0 — silent wrong
   values (bug-c-multidim-brace-elision-flattens-rows, b367). The GLOBAL path
   (recursive walker) was already correct. Expected output = gcc's exactly. */
#include <stdio.h>
int main(void) {
  int a[2][3] = {{1},{2}};             /* short rows */
  int b[2][3] = {{1,2,3},{4,5,6}};     /* full rows */
  int c[2][3] = {1,2,3,4,5,6};         /* full elision */
  int d[3][2] = {{9},{8,7}};           /* mixed short */
  int e[2][2][2] = {{{1},{2}},{{3}}};  /* 3-D short */
  float f[2][2] = {{1.5f},{2.5f}};
  printf("a=%d %d %d %d\n", a[0][0], a[0][1], a[1][0], a[1][2]);
  printf("b=%d %d %d\n", b[0][2], b[1][0], b[1][2]);
  printf("c=%d %d %d\n", c[0][2], c[1][0], c[1][2]);
  printf("d=%d %d %d %d\n", d[0][0], d[0][1], d[1][0], d[1][1]);
  printf("e=%d %d %d %d %d\n", e[0][0][0], e[0][0][1], e[0][1][0], e[1][0][0], e[1][1][0]);
  printf("f=%.1f %.1f %.1f\n", f[0][0], f[0][1], f[1][0]);
  return 0;
}
