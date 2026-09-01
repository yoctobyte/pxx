/* A LOCAL whose type is a struct with a function-pointer member.
 *
 * ParseCDeclType records an inline function-pointer declarator's name in
 * CTypeFnPtrName. A struct BODY containing `int (*f)(int)` sets that global
 * from the MEMBER declarator and leaves it set afterwards, so the outer
 * declaration saw leftover state from a construct that had already finished.
 * ParseCGlobalVarDecl guarded against exactly this with `baseTk = tyPointer`;
 * ParseCLocalDeclAST did not, so the local never consumed its own variable
 * name and the name parsed as an expression:
 *     warning: undeclared identifier 'tbl' used as value (treated as 0)
 *     error: expected C expression
 * Found building busybox's fnmatch, whose [:class:] table is exactly this shape.
 *
 * BOTH ARMS are pinned here. Rows 1-3 are the bug. Rows 4-5 are the path the
 * guard must NOT break -- a real inline function-pointer local, scalar and
 * array -- because a guard that fixes the struct case by disabling the fn-ptr
 * case would pass a test that only covered the first.
 */
#include <stdio.h>

static int add1(int c) { return c + 1; }
static int dbl(int c)  { return c * 2; }

struct Named { const char *n; int (*f)(int); };

int main(void) {
  /* 1: anonymous struct, fn-ptr member, scalar local */
  struct { int (*f)(int); } one = { add1 };
  /* 2: anonymous struct, fn-ptr member, ARRAY local with initialiser */
  struct { const char *n; int (*f)(int); } tbl[] = { { "a", add1 }, { "b", dbl } };
  /* 3: named struct, same shape -- the arm that already worked */
  struct Named nm[] = { { "c", dbl } };
  /* 4: a real inline function-pointer local */
  int (*fp)(int) = add1;
  /* 5: a real array of function pointers */
  int (*fps[2])(int) = { add1, dbl };

  printf("1 %d\n", one.f(10));
  printf("2 %s %d %s %d\n", tbl[0].n, tbl[0].f(10), tbl[1].n, tbl[1].f(10));
  printf("3 %s %d\n", nm[0].n, nm[0].f(10));
  printf("4 %d\n", fp(10));
  printf("5 %d %d\n", fps[0](10), fps[1](10));
  return 42;
}
