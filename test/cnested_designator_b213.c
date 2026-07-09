/* Regression: C99 nested / sub-level designators .a.j = v (and deeper .b.c.y,
   reordered, local + global). The aggregate-init walker handled one .name level
   then positional; a continuation .sub/[i] into an unbraced subaggregate now
   descends the full chain. gcc-verified. c-testsuite 00216 test_zero_init. */
struct C { int x, y; };
struct B { struct C c; int m; };
struct A { struct B b; int n; };
struct Sea { int i, j, k, l; };
struct Seb { struct Sea a; int r; };
struct Seb gb = { .a.j = 5, .r = 8 };
int main(void) {
  struct A a = { .b.c.y = 9, .n = 4 };
  struct Seb b = { .a.j = 5 };
  int ok = 1;
  if (!(a.b.c.x==0 && a.b.c.y==9 && a.b.m==0 && a.n==4)) ok = 0;
  if (!(b.a.i==0 && b.a.j==5 && b.a.k==0 && b.a.l==0 && b.r==0)) ok = 0;
  if (!(gb.a.i==0 && gb.a.j==5 && gb.r==8)) ok = 0;
  return ok ? 42 : 1;
}
