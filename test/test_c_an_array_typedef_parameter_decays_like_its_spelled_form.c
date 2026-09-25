/* A parameter declared through an ARRAY TYPEDEF decays exactly like the
 * spelled-out array parameter: `vec4 v` is `float v[4]`, `mat4 m` (typedef
 * vec4 mat4[4]) is `float m[4][4]`, and `vec4 m[]` is `float m[][4]`.
 *
 * The parameter site handled `T name[..]` and never looked at the typedef's own
 * dims, so `v[0]` read the POINTER ITSELF as a float and `m[i][j]` flattened
 * wrong. That is cglm's core shape: every glm_* function takes `mat4 m`, and
 * test_glm_mul was the first thing to fail. The float values are non-default
 * (3.5, 5.25, 9.75), so an unread element cannot pass.
 * Expected is gcc's output. */
#include <stdio.h>
typedef float vec4[4];
typedef vec4 mat4[4];
static void p1(mat4 m) { printf("p1 %g %g %g\n", m[0][0], m[1][1], m[2][3]); }
static void p2(float m[4][4]) { printf("p2 %g %g %g\n", m[0][0], m[1][1], m[2][3]); }
static void p3(vec4 *m) { printf("p3 %g %g %g\n", m[0][0], m[1][1], m[2][3]); }
static void p5(vec4 v) { printf("p5 %g %g\n", v[0], v[3]); }
static void mul(mat4 m1, mat4 m2, mat4 dest) {
  mat4 t; int i, j, k;
  for (i = 0; i < 4; i++) for (j = 0; j < 4; j++) { float s = 0; for (k = 0; k < 4; k++) s += m1[k][j] * m2[i][k]; t[i][j] = s; }
  for (i = 0; i < 4; i++) for (j = 0; j < 4; j++) dest[i][j] = t[i][j];
}
static void copy(mat4 src, mat4 dst) { mul(src, (mat4){{1}, {0, 1}, {0, 0, 1}, {0, 0, 0, 1}}, dst); }
static float rowsum(vec4 rows[], int n) { float s = 0; int i; for (i = 0; i < n; i++) s += rows[i][i] + rows[i][3]; return s; }
static void setv(vec4 v, float x) { v[0] = x; v[3] = x * 2; }
static int sz(mat4 m, vec4 v) { return (int)(sizeof(m) + sizeof(v) + sizeof(*v)); }
int main(void) {
  mat4 d = {{3.5f, 0, 0, 0}, {0, 5.25f, 0, 0}, {0, 0, 1, 9.75f}, {0, 0, 0, 1}};
  mat4 a = {{1.5f, 2}, {0, 2.25f}, {0, 0, 1}, {0.5f, 0, 0, 1}}, b = {{5}, {0, 6}, {0, 0, 7}, {1, 1, 1, 1}}, r, c;
  vec4 v = {0};
  int i;
  p1(d); p2(d); p3(d); p5(d[2]);
  mul(a, b, r);
  for (i = 0; i < 4; i++) printf("%g %g %g %g\n", r[i][0], r[i][1], r[i][2], r[i][3]);
  copy(r, c);
  printf("%g %g %g\n", c[0][0], c[3][3], rowsum(c, 4));
  setv(v, 1.25f); setv(c[2], 3.5f);
  printf("%g %g %g %g\n", v[0], v[3], c[2][0], c[2][3]);
  printf("%d\n", sz(a, v));
  return 0;
}
