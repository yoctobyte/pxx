/* AN ARRAY TYPEDEF WHOSE ELEMENT IS A STRUCT IS AN ARRAY.
 *
 * `typedef P PA[2];` over a struct P recorded no dims, so PA was one P:
 * `struct { char c; PA ps; int after; }` was 16 bytes (gcc 24), `q.ps[1]` lay
 * past the space reserved for it, and a local `PA x;` was refused at `x[1].b`
 * ("no member named 'b'"). Array typedefs of scalars were right; only the
 * struct element was left out at the typedef's registration.
 * bug-c-an-array-typedef-of-structs-is-not-modelled
 *
 * The first block writes each member's LAST element and reads its neighbours:
 * an under-sized member overlaps the next one, and a size can be right while
 * the layout is not. The rest varies the shape -- nested typedefs, a double
 * element, locals, globals, designated and nested initializers, arrays of the
 * typedef, a pointer to it, parameters, a struct copy, a union, a compound
 * literal -- and reaches the last element each time. An array compound literal
 * indexed and then selected, `((P[3]){...})[2].b`, read `.a` whatever the
 * spelling: the element's record was not resolved through that base.
 *
 * NOT covered, on purpose: a function RETURNING `PA *` has no pointee shape
 * (any array typedef, not just this one).
 * bug-c-a-function-returning-a-pointer-to-an-array-has-no-pointee-shape
 *
 * va_list was `typedef struct __pxx_va_elem va_list[1];` in pxx's stdarg.h and
 * is now the plain struct pxx always treated it as; the varargs tests cover it.
 *
 * Diffed against gcc's own output, native and (test-i386) against gcc -m32.
 */
#include <stdio.h>
#include <string.h>

typedef struct { int a, b; } P;
typedef P PA[2];
typedef PA PA2[3];
typedef struct { double d; char c; } D;
typedef D DA[3];

struct Q { char c; PA ps; int after; };
struct R { PA2 grid; D tail; };
union U { PA pa; long long raw[2]; };

#define PR(x) printf("%s = %ld\n", #x, (long)(x))
#define FR(x) printf("%s = %g\n", #x, (double)(x))

PA gpa = {{1, 2}, {3, 4}};
PA2 g2 = {{{1, 2}, {3, 4}}, {{5, 6}, {7, 8}}, {{9, 10}, {11, 12}}};
DA gda = {{1.5, 'a'}, {2.5, 'b'}, {3.5, 'c'}};
struct Q gq = {'q', {{5, 6}, {7, 8}}, 42};

static int sumpa(PA x) { return x[0].a + x[1].b; }
static int sum2(PA2 x) { return x[2][1].b + x[0][0].a; }
static int byq(struct Q q) { return q.ps[1].b + q.after; }

int main(void) {
  struct Q q, q2;
  struct R r;
  union U u;
  PA x = {{10, 20}, {30, 40}};
  PA des = {[1] = {.b = 7}};
  PA arr[3];
  PA *p = &x;
  PA2 z;
  DA da = {{0.5, 'x'}, {1.5, 'y'}, {2.5, 'z'}};
  P *ep = x;

  /* writes must not clobber their neighbours */
  q.after = 99; q.c = 'z'; q.ps[1].b = 7; q.ps[0].a = 5;
  PR(q.after); PR(q.c); PR(q.ps[1].b);
  memset(&r, 0, sizeof r); r.tail.c = 'T'; r.tail.d = 2.5; r.grid[2][1].b = 5;
  PR(r.tail.c); FR(r.tail.d); PR(r.grid[2][1].b);
  memset(arr, 0, sizeof arr); arr[2][1].b = 6; arr[1][0].a = 3;
  PR(arr[1][0].a); PR(arr[2][1].b); PR(arr[2][0].b);

  PR(sizeof(struct Q)); PR(sizeof q.ps); PR(sizeof(PA)); PR(sizeof(PA2)); PR(sizeof(DA));
  PR(sizeof(struct R)); PR(sizeof r.grid[1]); PR(sizeof(union U)); PR(sizeof arr); PR(sizeof arr[1]);

  /* initializers: local, designated, nested, global, double element */
  PR(x[1].b); PR(des[1].b); PR(des[0].a); PR(gpa[1].b); PR(g2[2][1].b); PR(g2[1][0].b);
  PR(gq.ps[1].b); PR(gq.after); PR(gda[2].c); FR(gda[2].d); PR(da[2].c); FR(da[2].d);

  /* through a pointer to the typedef, and its element */
  PR((*p)[1].b); PR(p[0][1].a); PR(sizeof *p); PR((char *)(p + 1) - (char *)p); PR(ep[1].b);
  PR((char *)(&x + 1) - (char *)&x); PR(sizeof(*(&x))); PR((&x)[0][1].b);

  /* copies, parameters, a union, a compound literal */
  q2 = q; q2.ps[1].b = 77;
  PR(q.ps[1].b); PR(q2.ps[1].b); PR(q2.after); PR(byq(q2));
  u.pa[1].b = 3; u.pa[0].a = 1; PR(u.pa[1].b); PR((int)(u.raw[1] >> 32));
  PR(sumpa(x)); PR(sum2(g2)); PR(((PA){{1, 2}, {3, 4}})[1].b); PR(((P[3]){{1, 2}, {3, 4}, {5, 6}})[2].b);

  /* a row of the 2-D typedef */
  memcpy(z, g2, sizeof z);
  PR(z[2][1].b); PR(&z[2] - &z[0]); PR((char *)(&z[1] + 1) - (char *)&z[1]);
  PR(sizeof(*(&z[1]))); PR((*(&z))[2][1].b); PR((*(&z[2]))[1].a);
  return 0;
}
