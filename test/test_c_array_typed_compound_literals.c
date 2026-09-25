/* Array-typed compound literals of every shape: through an array typedef
 * (`(vec4){..}`), through a typedef of an array typedef (`(mat4){..}`, which is
 * cglm's GLM_MAT4_IDENTITY), a multi-dimensional cast (`(float[4][4]){..}`),
 * an unsized first dimension over rows, record elements, and designators.
 * All of them were refused ("expected '}'", "expected ')'", "expected C
 * expression") except the flat one-dimensional scalar form. The literal is
 * shaped like a local array declaration and filled by the same brace-elision
 * walker. sizeof of each is the whole array; a multi-dimensional one subscripts
 * by rows.
 *
 * A cast to a POINTER TO ARRAY, `(float (*)[4])p`, had the same row blindness:
 * the abstract `(*)[N]` declarator fell to the function-pointer arm, so
 * `((float (*)[4])p)[3][3]` read p[6] and printf got a float as an integer.
 * Expected is gcc's output. */
#include <stdio.h>
typedef float vec4[4];
typedef vec4 mat4[4];
typedef int row3[3];
struct pt { int x, y; };
static int rowsum(int (*)[3], int);
static int twice(int x) { return 2 * x; }
static float tr(float (*m)[4]) { return m[0][0] + m[1][1] + m[2][2] + m[3][3]; }
static int sumr(int (*r)[3], int n) { int s = 0, i, j; for (i = 0; i < n; i++) for (j = 0; j < 3; j++) s += r[i][j] * (i + 1); return s; }
int main(void) {
  struct pt *p = (struct pt[2]){{1, 2}, {3, 4}};
  int (*u)[2] = (int[][2]){{1, 2}, {3, 4}, {5}};
  int *d = (int[5]){[3] = 9, [1] = 4};
  float (*vv)[4] = (vec4[2]){{1, 2}, {3, 4, 5, 6}};
  int (*r)[3] = (row3[]){1, 2, 3, 4, 5};
  int i, acc = 0;
  printf("%d %d %d %d\n", p[0].x, p[0].y, p[1].x, p[1].y);
  printf("%d %d %d %d %d %d\n", u[0][0], u[0][1], u[1][0], u[1][1], u[2][0], u[2][1]);
  printf("%d %d %d %d %d\n", d[0], d[1], d[2], d[3], d[4]);
  printf("%g %g %g %g\n", vv[0][1], vv[0][3], vv[1][0], vv[1][3]);
  printf("%d %d %d\n", r[1][0], r[1][1], r[1][2]);
  printf("%g %g\n", tr((mat4){{1}, {0, 2}, {0, 0, 3}, {0, 0, 0, 4}}), tr((float[4][4]){1, 0, 0, 0, 0, 5}));
  for (i = 0; i < 3; i++) { int *q = (int[3]){i, i, i}; q[1] += 10; acc += q[0] + q[1] + q[2]; }
  printf("%d %d\n", acc, sumr((int[2][3]){{1, 2, 3}, {4, 5, 6}}, 2));
  printf("%d %d %d %d\n", (int)sizeof((int[][2]){{1, 2}, {3, 4}, {5}}), (int)sizeof((vec4[2]){0}),
         (int)sizeof((row3[]){{1}, {2}}), (int)sizeof((struct pt[3]){0}));
  printf("%g\n", ((mat4){{1, 2}, {3, 4}})[1][0]);
  printf("%g %g %d\n", ((vec4){1, 2, 3, 4})[2], ((float (*)[4])(mat4){{1}, {0, 1}, {0, 0, 1}, {0, 0, 0, 1}})[3][3], (int)sizeof((mat4){0}));
  {
    float mm[4][4] = {{1}, {0, 2}, {0, 0, 3}, {0, 0, 0, 4}};
    int iz[2][3] = {{1, 2, 3}, {4, 5, 6}};
    void *vp = mm;
    int (*fp)(int) = (int (*)(int))twice;
    printf("%g %g %d %d\n", ((float (*)[4])vp)[3][3], ((float (*)[4])mm)[1][1], ((int (*)[3])iz)[1][2], 9);
    printf("%d %d %d\n", rowsum(iz, 2), (int)sizeof(int (*)[3]), fp(21));
    printf("%g\n", ((float (*)[4])(mat4){{1}, {0, 1}, {0, 0, 1}, {0, 0, 0, 7}})[3][3]);
  }
  return 0;
}
static int rowsum(int (*r)[3], int n) { return r[n - 1][0] + r[0][2]; }
