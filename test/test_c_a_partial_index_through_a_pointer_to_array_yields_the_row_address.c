/* A partial subscript through a pointer to array decays to the sub-array's
   ADDRESS (C 6.3.2.1p3), the way *(p+i) does; only a full index loads.
   cglm's glm_rotate_make passes m[0] of a `mat4 m` param as a vec4. */
#include <stdio.h>
typedef float vec4[4];
typedef vec4 mat4[4];
struct pt { int x, y; };

static void scale(float *v, float s, float *dest) { int i; for (i = 0; i < 3; i++) dest[i] = v[i] * s; }
static int rowsum(int (*m)[4], int r) { int *row = m[r]; return row[0] + row[1] + row[2] + row[3]; }
static void setrow(mat4 m, float s) { scale(m[1], s, m[0]); }

int main(void) {
  float x[3][4] = {{1, 2, 3, 4}, {5, 6, 7, 8}, {9, 10, 11, 12}};
  float (*p)[4] = x;
  float *r = p[1];
  int g[2][4] = {{1, 2, 3, 4}, {10, 20, 30, 40}};
  float c[2][3][4];
  float (*q)[3][4] = c;
  float *qr;
  struct pt pts[2][2] = {{{1, 2}, {3, 4}}, {{5, 6}, {7, 8}}};
  struct pt (*pp)[2] = pts;
  struct pt *prow = pp[1];
  mat4 m = {{1, 2, 3, 4}, {5, 6, 7, 8}};
  int i, j, k;
  for (i = 0; i < 2; i++) for (j = 0; j < 3; j++) for (k = 0; k < 4; k++) c[i][j][k] = i * 100 + j * 10 + k;
  printf("row %g %g %g\n", r[0], r[3], p[2][1]);
  printf("param %d %d\n", rowsum(g, 0), rowsum(g, 1));
  qr = q[1][2];                   /* partial at depth 2 of a 2-D pointee */
  printf("deep %g %g %g\n", qr[0], qr[3], (q[1])[1][2]);
  printf("full %g\n", q[1][2][3]);
  printf("step %g\n", (p[0] + 1)[0]);
  printf("rec %d %d\n", prow[1].x, prow[1].y);
  setrow(m, 2.0f);
  printf("mat4 %g %g %g\n", m[0][0], m[0][1], m[0][2]);
  return 0;
}
