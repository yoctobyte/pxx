/* A pointer to an ARRAY TYPEDEF, and compound literals whose element is a
 * pointer.
 *
 * `mat4 *q` (typedef vec4 mat4[4]) is the same type as `float (*q)[4][4]`, but
 * it recorded only the first dim (a local) or none (a parameter, a cast), so
 * `(*q)[1][1]` read the wrong element. `(int *[]){&x, &y}` and cglm's
 * `(mat4 *[]){&a, &b}` were refused with "expected ')'". `(0, arr)[i]->f`
 * lost the record of an array of struct pointers.
 * Expected is gcc's output. */
#include <stdio.h>
typedef float vec4[4];
typedef vec4 mat4[4];
struct pt { int x, y; };
static float one(mat4 *m) { return (*m)[1][1]; }
static float two(float (*m)[4][4]) { return (*m)[2][2]; }
static int sumpp(int **pp, int n) { int s = 0; while (n--) s += *pp[n]; return s; }
static float vsum(vec4 *v, int n) { float s = 0; int i; for (i = 0; i < n; i++) s += v[i][i]; return s; }
int main(void) {
  int x = 3, y = 4;
  mat4 b = {{5}, {0, 6}, {0, 0, 7}};
  mat4 *q = &b;
  vec4 *rows = b;
  struct pt p = {7, 8};
  struct pt *arr[1] = {&p};
  void *vp = &b;
  printf("%g %g %g %g\n", (*q)[1][1], one(&b), two(&b), vsum(rows, 3));
  printf("%g %g\n", (*(mat4 *)vp)[2][2], ((vec4 *)vp)[1][1]);
  printf("%d\n", *((int *[]){&x, &y})[1]);
  printf("%d\n", *((int *[2]){&x, &y})[0] + y);
  printf("%d %d\n", sumpp((int *[]){&x, &y, &x}, 3), ((struct pt *[1]){&p})[0]->y);
  printf("%d %d\n", arr[0]->y, (0, arr)[0]->y);
  printf("%d %d\n", (int)sizeof((int *[]){&x, &y, &x}), (int)sizeof((char *[4]){"a"}));
  printf("%s\n", ((const char *[]){"zero", "one", "two"})[2]);
  printf("%d\n", (int)sizeof((mat4 *[]){&b, &b}));
  return 0;
}
