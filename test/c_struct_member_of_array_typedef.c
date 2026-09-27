/* A STRUCT MEMBER WHOSE TYPE IS AN ARRAY TYPEDEF IS AN ARRAY, AND A MEMBER
 * THAT POINTS AT ONE KNOWS THE SHAPE IT POINTS AT.
 *
 * The struct builder never read the typedef's dims. So `mat4 m;` as a member
 * was laid out as ONE float: `struct { int k; mat4 m; vec4 v; int tail; }` was
 * 12 bytes where gcc says 88, and `typedef int arr3[3]; struct { arr3 a; int
 * after; }` was 8 (gcc 16) with `u.a[1] = 2` landing in `after`. A member
 * `mat4 *p;` had no pointee shape: `sizeof *s.p` 4 (gcc 64), `(*s.p)[2][2]`
 * read 0, and `(*s.m[0])[1][1]` through `mat4 *m[3];` segfaulted. cglm's
 * struct API (`union mat2x3s { mat2x3 raw; ... }`) crashed on the first test.
 * Same on v441 and v443.
 * bug-c-a-struct-field-that-points-at-an-array-typedef-has-no-pointee-dims
 *
 * THE FIRST BLOCK IS NOT A SIZE. Every member write is followed by a read of
 * its NEIGHBOURS: an under-sized member overlaps the next one, and sizeof can
 * be right while the layout is not. A size assertion cannot see an overlap.
 *
 * The rest varies the shape: 1- and 2-level typedefs, a bracketed array of a
 * typedef (`vec4 rows[2]`), the member inside an anonymous struct and a union,
 * brace initialisers (local and file-scope), a struct copy and a by-value
 * argument, and pointer members -- scalar, 1-D and 2-D arrays of them, through
 * `.` and `->`, sized, indexed, dereferenced and stepped.
 *
 * NOT covered, on purpose: an array typedef of STRUCTS (`typedef P PA[2]`),
 * which the typedef table does not model at all (a local `PA x;` is refused;
 * pxx's own va_list has that shape). bug-c-an-array-typedef-of-structs-is-not-modelled
 *
 * THE MX BLOCK puts the two spellings of "points at an array" side by side in
 * one struct: `int (*p)[4]` (a declarator) next to `mat4 m;` and `mat4 *q;`
 * (a typedef), each sized with and without parentheses and stepped. The
 * parenthesised `sizeof(*(s.p))` answered 4 on v443 while `(s.p)+1` also
 * stepped 4, so a size-equals-stride test passed on two wrongs; fixing the
 * stride left the size at 8. regression-test-core-c-sizeof-ptr-to-array-field
 *
 * Diffed against gcc's own output, so no expected value is transcribed here.
 */
#include <stdio.h>
#include <string.h>

typedef int arr3[3];
typedef float vec3[3];
typedef float vec4[4];
typedef vec4 mat4[4];
typedef vec3 mat2x3[2];

#define P(x) printf("%s = %d\n", #x, (int)(x))
#define F(x) printf("%s = %g\n", #x, (double)(x))

struct U { arr3 a; int after; };
struct T { int k; mat4 m; vec4 v; int tail; };
struct R { int k; vec4 rows[2]; int after; };
struct W { char c; struct { vec3 a; mat2x3 b; }; int z; };
typedef struct { float x, y, z; } vec3s;
typedef union { mat2x3 raw; vec3s col[2]; struct { float m00, m01, m02, m10, m11, m12; }; } mat2x3s;
struct MX { int k; int (*p)[4]; mat4 m; mat4 *q; int (*p2)[2][3]; vec4 *v; int tail; };
struct PF { int k; mat4 *p; vec4 *v; mat4 *m[3]; mat4 *mm[2][2]; int tail; };

static struct T gt = {7, {{1, 2, 3, 4}, {5, 6, 7, 8}}, {9, 10, 11, 12}, 42};

static float sum(struct T t) { return t.m[1][2] + t.v[3] + t.tail; }
static float chk(mat2x3 m) { return m[0][0] + m[1][2] + m[1][1]; }

int main(void) {
  struct U u;
  struct T t = {1, {{1}, {0, 2}, {0, 0, 3}, {0, 0, 0, 4}}, {5, 6, 7, 8}, 99};
  struct T c;
  struct R r;
  struct W w;
  mat2x3s ms = {{{0, 0, 0}, {0, 0, 7}}};
  mat4 a = {{1}, {0, 2}, {0, 0, 3}};
  vec4 q = {1, 2, 3, 4};
  struct PF f, *pf = &f;
  struct MX x, *px = &x;
  int i4[4] = {1, 2, 3, 4};
  int i23[2][3] = {{1, 2, 3}, {4, 5, 6}};
  int (*sp)[4] = &i4;

  /* writes must not clobber their neighbours */
  u.after = 99; u.a[0] = 1; u.a[1] = 2; u.a[2] = 3;
  P(u.after); P(u.a[1]);
  r.k = 11; r.after = 44; r.rows[1][3] = 8; r.rows[0][0] = 1;
  P(r.k); P(r.after); F(r.rows[1][3]);
  t.m[3][3] = 5; t.v[3] = 6;
  P(t.k); F(t.m[3][3]); F(t.v[3]); P(t.tail);
  memset(&w, 0, sizeof w); w.z = 5; w.b[1][2] = 6; w.a[2] = 3;
  P(w.z); F(w.b[1][2]); F(w.a[2]); P(w.c);

  P(sizeof(struct U)); P(sizeof(struct T)); P(sizeof(struct R)); P(sizeof(struct W));
  P(sizeof u.a); P(sizeof t.m); P(sizeof t.m[1]); P(sizeof r.rows); P(sizeof w.b); P(sizeof w.b[1]);

  /* initialisers, copies, by-value */
  F(t.m[2][2]); F(t.v[0]);
  c = t; F(c.m[3][3]); P(c.tail);
  F(gt.m[1][3]); F(gt.v[1]); P(gt.tail); F(sum(gt));

  /* cglm's struct API: an array-typedef member of a union */
  P(sizeof ms); F(chk(ms.raw)); F(ms.raw[1][2]); F(ms.m12); F(ms.col[1].z);

  /* pointer members */
  f.k = 3; f.tail = 4; f.p = &a; f.v = &q; f.m[0] = &a; f.m[2] = &a; f.mm[1][1] = &a; f.mm[0][1] = &a;
  P(sizeof(struct PF)); P(sizeof f.m); P(sizeof f.m[0]); P(sizeof f.mm);
  P(sizeof *f.p); P(sizeof f.p[0]); P(sizeof *f.v); P(sizeof *f.m[0]); P(sizeof *f.mm[1][1]);
  F((*f.p)[2][2]); F(f.p[0][1][1]); F((*pf->p)[1][1]); F((*f.v)[3]); F((*pf->v)[2]);
  F((*f.m[0])[1][1]); F(f.m[2][0][2][2]); F((*pf->m[2])[0][0]);
  F((*f.mm[1][1])[2][2]); F(f.mm[0][1][0][1][1]);
  P((char *)(f.p + 1) - (char *)f.p); P((char *)(pf->v + 1) - (char *)pf->v);
  P((char *)(f.m[0] + 1) - (char *)f.m[0]); P((char *)(f.mm[1][1] + 1) - (char *)f.mm[1][1]);
  P(f.k); P(f.tail);

  /* both spellings in one struct, parenthesised and not */
  memset(&x, 0, sizeof x); x.k = 1; x.tail = 2;
  x.p = &i4; x.q = &a; x.p2 = &i23; x.v = &q; x.m[3][3] = 9;
  P(sizeof(struct MX)); P(sizeof x.m); P(x.k); P(x.tail); F(x.m[3][3]);
  P(sizeof *x.p); P(sizeof(*x.p)); P(sizeof(*(x.p))); P(sizeof(*((x.p)))); P(sizeof *(x.p));
  P(sizeof *x.q); P(sizeof(*(x.q))); P(sizeof(*(px->q))); P(sizeof *(px->p));
  P(sizeof(*(x.p2))); P(sizeof(*(x.v))); P(sizeof(*(x.m))); P(sizeof(*(x.m[1])));
  P(sizeof(*(sp))); P(sizeof *(sp)); P(sizeof(*(sp + 1)));
  P((char *)((x.p) + 1) - (char *)(x.p)); P((char *)((x.q) + 1) - (char *)(x.q));
  P((char *)((px->p2) + 1) - (char *)(px->p2)); P((char *)((x.m) + 1) - (char *)(x.m));
  P((*x.p)[3]); P((*(x.p))[2]); F((*(x.q))[2][2]); P((*(px->p2))[1][2]);
  P(x.p2[0][1][2]); F(x.q[0][1][1]); F((*x.v)[3]);
  return 0;
}
