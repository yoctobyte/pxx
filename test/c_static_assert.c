/* `_Static_assert` is EVALUATED, at every scope C11 allows one.
   bug-c-_Static_assert-is-refused-at-block-scope

   THIS FILE IS THE HALF THAT MUST COMPILE AND RUN. The four FALSE rows — the
   ones that must REFUSE, which are the entire point — cannot live here, because
   the harness has no must-not-compile form. They are Makefile rows beside this
   one, one file per site, and the ticket carries the gcc measurement that fixes
   each expected answer.

   WHY THE TRUE ROWS ARE NOT FILLER. Before this, a false assertion at file,
   struct and union scope compiled SILENTLY, and the obvious repair — evaluate
   it — can be got wrong in the direction that refuses correct programs instead.
   These rows are the control for that: an assertion that HOLDS must be
   invisible, and a struct carrying one must lay out exactly as it did without
   it. The sizeof and field reads below are what make the second claim testable
   rather than assumed; a struct whose assertion perturbed its layout would
   still compile.

   THE `sizeof` ROWS ARE DELIBERATELY SELF-REFERENTIAL about the enclosing type,
   because that is the idiom static assertions exist for — the ABI layout check
   written next to the layout it is about. A `_Static_assert` on a constant like
   `1 == 1` proves the parser runs; one on `sizeof(struct S)` proves the
   evaluator sees the type. */
#include <stdio.h>

_Static_assert(sizeof(int) == 4, "file scope: int is 4");
static_assert(sizeof(long) == 8, "file scope: the static_assert spelling");

struct S {
  int  a;
  long b;
  _Static_assert(sizeof(int) <= sizeof(long), "struct scope: member ordering");
};

union U {
  int    i;
  double d;
  _Static_assert(sizeof(double) == 8, "union scope");
};

int main(void) {
  int fails = 0;
  struct S s;
  union U u;

  _Static_assert(sizeof(struct S) == 16, "block scope: S is two eightbytes");

  s.a = 7;
  s.b = 9;
  if (s.a != 7 || s.b != 9) { printf("FAIL struct fields: %d %ld\n", s.a, s.b); fails++; }
  if (sizeof(struct S) != 16) { printf("FAIL struct size: %zu\n", sizeof(struct S)); fails++; }

  u.d = 2.5;
  if (u.d != 2.5) { printf("FAIL union: %f\n", u.d); fails++; }
  if (sizeof(union U) != 8) { printf("FAIL union size: %zu\n", sizeof(union U)); fails++; }

  if (!fails) printf("static assert: 4 scopes, layout intact\n");
  return fails != 0;
}
