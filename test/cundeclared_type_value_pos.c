/* The other half of bug-cfront-undeclared-type-in-cast-treated-as-zero: an
   undeclared identifier in VALUE position must keep degrading to 0 with a
   warning, not become an error. That leniency is what carries the corpora
   through tokens a self-referential or unmodelled macro leaves behind, so the
   cast fix must not widen into it.

   The shapes below are exactly the ones the cast check deliberately does NOT
   claim: `(X)` alone, and `(X)` followed by an operator that could equally be
   a binary continuation. */

#include <stdio.h>

int main(void) {
  int a = UNMODELLED_MACRO_A;                 /* bare value position     */
  int b = (UNMODELLED_MACRO_B);               /* parenthesised value     */
  int p = 7;
  int c = (UNMODELLED_MACRO_C) + p;           /* `(X) +` stays a binop   */
  int d = (UNMODELLED_MACRO_D) - p;           /* `(X) -` stays a binop   */
  if (a != 0) { printf("a=%d\n", a); return 1; }
  if (b != 0) { printf("b=%d\n", b); return 1; }
  if (c != 7) { printf("c=%d\n", c); return 1; }
  if (d != -7) { printf("d=%d\n", d); return 1; }
  return 42;
}
