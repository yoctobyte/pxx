/* Calling through a function-pointer TABLE -- the ordinary C dispatch idiom --
   failed to PARSE in two shapes, while four neighbouring spellings of the same
   thing worked:

     binop tab[2] = { add, mul };   / * inside a function * /
     tab[0](5, 6);                  / * error: unexpected token * /

     struct H { binop f[2]; };
     h.f[0](5, 6);                  / * error, at ANY scope * /

   Working all along: the same local declaration at FILE scope, the raw
   `int (*tab[2])(int,int)` spelling at either scope, and going through a temp
   (`binop g = tab[0]; g(5,6)`).

   1. The LOCAL array declaration path set the pointer metadata but never
      SymElemProcSig -- the `tab[i](args)` channel -- so the call suffix had no
      signature to bind. (Not SymProcSig: that marks the array VARIABLE as a
      proc value and corrupts indexing.)
   2. `s.f[i](args)` was missing from CalleeSig entirely: it handles AN_INDEX
      over an AN_IDENT, but not over an AN_FIELD.

   Every expectation is gcc -O0's.
   bug-c-a-local-typedef-d-function-pointer-array-is-not-callable
   bug-c-a-struct-field-function-pointer-array-is-not-callable */
#include <stdio.h>

static int add(int a, int b) { return a + b; }
static int mul(int a, int b) { return a * b; }
static int sub(int a, int b) { return a - b; }

typedef int (*binop)(int, int);

struct H { binop f[3]; int k; };

static binop gtab[2] = { add, mul };
static struct H gh = { { add, mul, sub }, 7 };

int main(void) {
  binop ltab[3] = { add, mul, sub };
  int (*rawtab[2])(int, int) = { add, mul };
  struct H lh = { { add, mul, sub }, 9 };
  struct H *p = &lh;
  binop nolist[2];
  binop g;
  int i;

  /* the two shapes that did not parse */
  printf("local  %d %d %d\n", ltab[0](5, 6), ltab[1](5, 6), ltab[2](5, 6));
  printf("field  %d %d %d\n", lh.f[0](5, 6), lh.f[1](5, 6), lh.f[2](5, 6));
  printf("gfield %d %d\n", gh.f[0](5, 6), gh.f[1](5, 6));
  printf("arrow  %d %d\n", p->f[0](5, 6), p->f[1](5, 6));

  /* a runtime index, not a constant one */
  i = 1;
  printf("varidx %d %d\n", ltab[i](5, 6), lh.f[i](5, 6));
  for (i = 0; i < 3; i++) printf("%d ", ltab[i](12, 4));
  printf("\n");

  /* an explicit deref of the element */
  printf("deref  %d %d\n", (*ltab[0])(5, 6), (*lh.f[1])(5, 6));

  /* declared without an initializer, then filled */
  nolist[0] = sub; nolist[1] = add;
  printf("nolist %d %d\n", nolist[0](9, 4), nolist[1](9, 4));

  /* the spellings that already worked, so the fix is proved not to move them */
  printf("global %d %d\n", gtab[0](5, 6), gtab[1](5, 6));
  printf("raw    %d %d\n", rawtab[0](5, 6), rawtab[1](5, 6));
  g = ltab[2];
  printf("temp   %d\n", g(5, 6));
  printf("direct %d\n", add(5, 6));
  printf("plain  %d %d\n", lh.k, gh.k);
  return 0;
}
