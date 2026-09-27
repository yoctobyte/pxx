/* THE ADDRESS OF AN OBJECT POINTS AT THE WHOLE OBJECT.
 *
 * In C, `&x` is a pointer to x's type, so `&x + 1` steps sizeof x. pxx stepped
 * ONE BYTE for every `&x` -- an int, a struct, a field, a pointer, an array --
 * because the stride rule kept Pascal's untyped-`@` default. For an array the
 * damage went further: `&a` had no pointer-to-array type at all, so
 * `sizeof *&a` was the element, and `&m[1]` of a row was the row's decayed
 * pointer, so `&m[1] + 1` stepped one element, `&m[1] - &m[0]` was 3 on
 * `int m[2][3]` (gcc 1), and `(&m[0])[1][1]` read m[0][4]. A parenthesised row
 * `sizeof((m[0]))` answered a pointer. At file scope `int (*r)[3] = &g[1];`
 * was left NULL.
 * bug-c-the-address-of-an-array-has-no-pointer-to-array-type
 *
 * Each row reads the LAST element of what it walks, where a short stride or a
 * short extent is the one that shows. Diffed against gcc's own output, native
 * and (test-i386) against gcc -m32, so no value is transcribed here.
 */
#include <stdio.h>
#include <string.h>

typedef float vec4[4];
typedef vec4 mat4[4];
struct T { int a, b, c; };
struct S { int k; int arr[3]; mat4 m; int tail; };
struct Pt { int x, y; };

#define D(p) ((long)((char *)((p) + 1) - (char *)(p)))
#define P(x) printf("%s = %ld\n", #x, (long)(x))
#define F(x) printf("%s = %g\n", #x, (double)(x))

int g23[2][3] = {{1, 2, 3}, {4, 5, 6}};
int g4[4] = {7, 8, 9, 10};
mat4 gm = {{1}, {0, 2}, {0, 0, 3}, {0, 0, 0, 4}};
/* file scope: every one of these was folded or skipped, one of them to NULL */
int (*gr)[3] = &g23[1];
int (*gr2)[3] = g23 + 1;
int (*gw)[4] = &g4;
int (*gall)[2][3] = &g23;
int *gq = &g23[1][2];
int *gz = g23[1];

static long parm(int a[4]) { return D(&a); }            /* a is a pointer here */
static int rowsum(int (*r)[3]) { return (*r)[0] + (*r)[1] + (*r)[2]; }
static int last4(int (*w)[4]) { return (*w)[3] + (int)sizeof *w; }

int main(void) {
  int i4[4] = {1, 2, 3, 4};
  int m23[2][3] = {{1, 2, 3}, {4, 5, 6}};
  int m3[2][3][4];
  mat4 a;
  struct S s, *ps = &s;
  struct T t;
  struct Pt pts[2][3];
  char buf[16];
  double d = 0;
  int i = 0, k = 1, *p = &m23[0][0];
  int it_sum = 0;
  int (*it)[3];

  for (i = 0; i < 24; i++) ((int *)m3)[i] = i;
  for (i = 0; i < 16; i++) ((float *)a)[i] = (float)i;
  for (i = 0; i < 6; i++) { ((struct Pt *)pts)[i].x = 10 + i; ((struct Pt *)pts)[i].y = 20 + i; }
  memset(&s, 0, sizeof s);
  s.arr[2] = 33; s.m[3][3] = 44; s.tail = 55;
  strcpy(buf, "hi!");

  /* every `&x` steps sizeof x */
  P(D(&i)); P(D(&d)); P(D(&t)); P(D(&t.c)); P(D(&p)); P(D(&*p));
  P(D(&i4)); P(D(&a)); P(D(&m23)); P(D(&g4)); P(D(&gm)); P(D(&s.arr)); P(D(&ps->m));
  P(D(&m23[1])); P(D(&a[2])); P(D(&m3[1])); P(D(&m3[1][2])); P(D(&pts[1])); P(D(&buf));
  P(parm(i4));

  /* ...and a difference of two of them counts objects */
  P(&m23[1] - &m23[0]); P(&g23[1] - &g23[0]); P(&a[3] - &a[0]); P(&m3[1][2] - &m3[0][0]);
  P((&g4 + 1) - &g4); P(&m23[1][2] - &m23[0][0]);

  /* sizeof through `*&` and a parenthesised row */
  P(sizeof *&i4); P(sizeof(*(&i4))); P(sizeof *&a); P(sizeof(*(&m23))); P(sizeof(*(&s.arr)));
  P(sizeof(*(&m23[1]))); P(sizeof *&m3[1]); P(sizeof(*&pts[1])); P(sizeof *&buf);
  P(sizeof((m23[1]))); P(sizeof((m3[0]))); P(sizeof((m3[1][2]))); P(sizeof((s.m[3])));
  P(sizeof((m23[i]))); P(sizeof(&m23[1])); P(sizeof(m23[0] + 0));

  /* values through `&array` and `&row`, the last element each time */
  P((*&i4)[3]); P((&i4)[0][3]); P((*(&m23))[1][2]); P((&m23)[0][1][2]);
  P((*(&m23[1]))[2]); P((&m23[0])[1][2]); P((*(&m3[1]))[2][3]); P((&m3[1][2])[0][3]);
  F((*&a)[3][3]); F((&a[1])[2][3]); P((*&s.arr)[2]); F((*(&ps->m))[3][3]);
  P((*(&pts[1]))[2].y); P((&pts[0])[1][2].x); P((*&buf)[2]); P(*(&*p + 5));
  P((*&s.arr)[2] = 66); P(s.arr[2]); P(s.tail);

  /* as arguments, in a ternary, and walked */
  P(rowsum(&m23[1])); P(rowsum(k ? &m23[0] : &m23[1])); P(last4(&i4)); P(last4(&g4));
  P((char *)((k ? &m23[0] : &m23[1]) + 1) - (char *)m23);
  for (it = &m23[0]; it < &m23[2]; it++) it_sum += (*it)[2];
  P(it_sum);

  /* file scope */
  P((*gr)[2]); P((*gr2)[2]); P((*gw)[3]); P((*gall)[1][2]); P(*gq); P(gz[2]);
  P(gr - &g23[0]); P((char *)gall - (char *)g23);
  return 0;
}
