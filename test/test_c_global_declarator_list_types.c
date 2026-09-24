/* Each declarator in a FILE-SCOPE list gets its own type: the `*` binds to
   the declarator, not to the specifiers. The block-scope path always did
   this; file scope gave every declarator the FIRST one's type, so `int *p, x;`
   made x a pointer and `int x, *p;` made p an int (`*p` segfaulted). Silent.
   Expected output is gcc's. */
#include <stdio.h>
struct T { int a, b; };
typedef int *IP;
int *p, x;
int y, *q;
int **pp, *p1, z;
struct T *tp, t, **tpp;
IP ia, ib;
char *s1 = "hi", c = 'A';
double d0, *dp, d1 = 2.5;
int main(void) {
  int v = 3;
  x = 7; p = &v; q = &v; p1 = &v; pp = &p1; z = 9;
  t.b = 5; tp = &t; tpp = &tp;
  ia = &v; ib = &x;
  dp = &d1;
  printf("%d %d\n", (int)sizeof p, (int)sizeof x);
  printf("%d %d %d\n", (int)sizeof y, (int)sizeof q, *q);
  printf("%d %d %d %d\n", (int)sizeof pp, (int)sizeof p1, **pp, z);
  printf("%d %d %d\n", (int)sizeof t, tp->b, (*tpp)->b);
  printf("%d %d %d\n", (int)sizeof ib, *ia, *ib);
  printf("%s %c %d\n", s1, c, (int)sizeof c);
  printf("%d %d %g\n", (int)sizeof d0, (int)sizeof dp, *dp);
  return 0;
}
