/* The other half of bug-cfront-undeclared-type-in-cast-treated-as-zero: WHICH
   diagnostic an undeclared identifier in VALUE position gets.

   Both halves are errors now
   (bug-c-an-undeclared-identifier-used-as-a-value-is-a-warning-not-an-error,
   2026-09-05) and that is exactly why this file still exists. When the two
   paths gave DIFFERENT verdicts — cast refused, value warned and folded to 0 —
   "it compiled" was enough to prove a shape had not been swallowed by the cast
   check. Now that both refuse, a test asserting only "this refuses" would pass
   no matter which path claimed the shape, so the assertion moved to the
   MESSAGE: each row below must say `used as value` and must NOT say
   `unknown type name ... in cast`.

   That is a stronger test than the one it replaces. The old row asserted a
   process exit status of 42, which was consistent with the cast check being
   absent entirely.

   The shapes are unchanged and they are the point: `(X)` alone, and `(X)`
   followed by an operator that could equally be a binary continuation, are
   exactly the ones the cast check deliberately does NOT claim. */

int main(void) {
  int p = 7;
  int a = UNMODELLED_MACRO_A;                 /* bare value position     */
  int b = (UNMODELLED_MACRO_B);               /* parenthesised value     */
  int c = (UNMODELLED_MACRO_C) + p;           /* `(X) +` stays a binop   */
  int d = (UNMODELLED_MACRO_D) - p;           /* `(X) -` stays a binop   */
  return a + b + c + d;
}
