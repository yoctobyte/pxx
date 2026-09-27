/* AN ARRAY OF POINTERS TO ARRAYS, AND A POINTER TO SUCH POINTERS, KNOW WHAT
 * THEIR ELEMENTS POINT AT.
 *
 * cglm's glm_mat4_mulN takes `mat4 *matrices[]` and counts it with
 * `sizeof m / sizeof m[0]`. The declaration folded the typedef's dims into the
 * ARRAY even when the declarator had a star, so `mat4 *m[3]` was a
 * float[3][4][4] of 192 bytes (gcc 24) and the count came out 1, silently.
 * Nothing recorded the element's pointee either, so `*m[i]` LOADED from the
 * matrix where C decays it, `(*m[i])[r][c]` read garbage, and the parameter
 * spelling (`mat4 *m[]` is `mat4 **m`) segfaulted.
 * bug-c-an-array-of-pointers-to-arrays-has-no-pointee-shape-so-deref-loads-instead-of-decaying
 *
 * The rows vary the shape on purpose: 1-, 2- and 3-level typedefs; local,
 * static, file-scope and parameter; the array, an element, and the element
 * dereferenced; indexing through `*m[i]` and through `m[i][0]`; pointer
 * arithmetic on the element (the stride row, which a size row cannot see); and
 * `mat4 **pp`, which carries the shape one level further in; and
 * `mat4 *m2[2][3]`, whose pointee spans share a slot row with its own. The scalar
 * `vec4 *r` rows ride along because unparenthesised `sizeof *r` and
 * `sizeof r[0]` were wrong for the plain pointer too (8 and 4, gcc 16 and 16).
 *
 * THE LAST BLOCK IS NOT A SIZE. A local with an unsized OUTER dimension
 * (`vec4 v[] = {...}`, `float a[][2] = {...}`) was allocated ONE ROW and
 * every further row was stored over the frame: cglm's perlin tests crashed on
 * return from exactly that. `before` and `after` bracket those locals; a size
 * assertion cannot observe an overrun.
 *
 * Diffed against gcc's own output, so no expected value is transcribed here.
 */
#include <stdio.h>

typedef float vec4[4];
typedef vec4 mat4[4];
typedef mat4 box2[2];

#define P(x) printf("%s = %d\n", #x, (int)(x))
#define F(x) printf("%s = %g\n", #x, (double)(x))

static mat4 ga = {{1}, {0, 2}}, gb = {{5}, {0, 6}, {0, 0, 7}};
static mat4 *gm[] = {&ga, &gb};
static mat4 **gpp = gm;
static mat4 *gp = &gb;
static mat4 *gm2[2][3] = {{&ga, &gb, &ga}, {&gb, &ga, &gb}};

static float tr(mat4 x) { return x[0][0] + x[1][1] + x[2][2] + x[3][3]; }

/* cglm's own signature, and its own count */
static float mulN(mat4 *m[], int n) {
  float s = 0; int i;
  P(sizeof m[0]); P(sizeof *m[0]);
  for (i = 0; i < n; i++) { s += (*m[i])[i][i]; s += tr(*m[i]); }
  return s;
}

static int cnt(mat4 *m[], int n) {
  float s = 0; int i;
  for (i = 0; i < n; i++) s += (*m[i])[1][1];
  return (int)s;
}

int main(void) {
  vec4 va = {1, 2, 3, 4}, vb = {5, 6, 7, 8};
  mat4 a = {{1}, {0, 2}}, b = {{5}, {0, 6}, {0, 0, 7}}, c = {{9}, {0, 9}, {0, 0, 9}, {0, 0, 0, 9}};
  box2 x, y;
  vec4 *v[] = {&va, &vb};
  mat4 *m[] = {&a, &b, &c};
  mat4 *n[5];
  box2 *bx[] = {&x, &y};
  mat4 **pp = m;
  vec4 *r = &va;
  static mat4 *sm[2] = {&ga, &gb};
  mat4 *m2[2][3] = {{&a, &b, &a}, {&b, &a, &b}};

  x[1][2][3] = 7; y[0][1][1] = 3;

  P(sizeof v); P(sizeof v[0]); P(sizeof *v[0]); P(sizeof v / sizeof v[0]);
  F((*v[1])[2]); F(v[0][0][3]); P((char *)(v[0] + 1) - (char *)v[0]);

  P(sizeof m); P(sizeof m[0]); P(sizeof *m[0]); P(sizeof m / sizeof m[0]);
  F((*m[1])[1][1]); F((*m[2])[3][3]); F(m[1][0][2][2]);
  P((char *)(m[0] + 1) - (char *)m[0]);
  P(sizeof n); P(sizeof *n[4]);

  P(sizeof bx); P(sizeof *bx[0]); F((*bx[0])[1][2][3]); F((*bx[1])[0][1][1]);

  P(sizeof pp); P(sizeof *pp); P(sizeof **pp);
  F((**pp)[1][1]); F((*pp[1])[2][2]); F(pp[1][0][1][1]);
  P((char *)(pp + 1) - (char *)pp); P((char *)(*pp + 1) - (char *)*pp);

  P(sizeof *r); P(sizeof r[0]); P(sizeof(*r)); F((*r)[2]);

  P(sizeof sm); P(sizeof *sm[1]); F((*sm[1])[1][1]);
  P(sizeof gm); P(sizeof *gm[0]); F((*gm[1])[2][2]); F(gm[0][0][1][1]);
  P(sizeof **gpp); F((**gpp)[1][1]); P(sizeof *gp); F((*gp)[2][2]);

  /* a MULTI-dim array of them: the pointee's spans live after the array's own */
  P(sizeof m2); P(sizeof m2[0]); P(sizeof m2[1][2]); P(sizeof *m2[1][2]);
  F((*m2[1][0])[2][2]); F(m2[0][1][0][1][1]); P((char *)(m2[1][1] + 1) - (char *)m2[1][1]);
  P(sizeof *gm2[0][1]); F((*gm2[1][2])[1][1]);

  F(mulN(m, 3));
  P(cnt((mat4 *[]){&a, &b}, 2));

  {
    int before = 111;
    vec4 uv[] = {{1, 2, 3, 4}, {5, 6, 7, 8}, {9, 10, 11, 12}};
    float ua[][2] = {1, 2, 3};
    char un[][4] = {"ab", "cd", "e"};
    int ux[][2][2] = {{{1}}, {{2}, {3, 4}}, {{5}}};
    int after = 222;
    P(sizeof uv); P(sizeof ua); P(sizeof un); P(sizeof ux);
    F(uv[2][1]); F(ua[1][0]); printf("%s %s\n", un[1], un[2]); P(ux[1][1][1]); P(ux[2][0][0]);
    P(before); P(after);
  }
  return 0;
}
