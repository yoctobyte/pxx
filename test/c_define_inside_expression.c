/* A #undef/#define inside a multi-line expression applies to the text AFTER
   it only. The preprocessor joins lines while a parenthesis is open, and
   expanded the whole joined `if (...)` after obeying every directive in it,
   so every NEQ took the last definition. libXt's Shell.c is this shape. A
   directive inside a MACRO CALL's argument list still collects and continues
   (the busybox getopt32long shape), checked below with ARGS.
   bug-c-a-define-inside-a-multi-line-expression-applies-to-the-text-before-it */
#include <stdio.h>
struct In { int a, b; };
struct S { struct In in; int a, c; } x = {{1, 2}, 10, 30}, y = {{1, 3}, 11, 30};
#define ARGS(a, b, c) ((a) * 100 + (b) * 10 + (c))
#define ON 1
int main(void)
{
  int r, q;
#define NEQ(f) (x.in.f != y.in.f)
  r = (NEQ(a) * 1 + NEQ(b) * 2
#undef NEQ
#define NEQ(f) (x.f != y.f)
       + NEQ(a) * 4 + NEQ(c) * 8);
#undef NEQ
  q = ARGS(1,
#if ON
           2,
#else
           9,
#endif
           3);
  printf("%d %d\n", r, q);
  return 0;
}
