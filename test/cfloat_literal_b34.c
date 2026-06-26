/* C float-literal LEXING: `1.5e1`, `2.` (trailing dot), `0.5`, exponents. Checked
   via comparisons in one condition. (int<->float numeric casts and computed
   doubles held across multiple branches are separate, filed float-codegen gaps.)
   Exit 42. */
int main(void) {
  double a = 1.5e1;   /* 15.0 */
  double b = 2.;      /* 2.0  */
  double c = 0.5;     /* 0.5  */
  double d = 1e2;     /* 100.0 */
  if (a > 14.9 && a < 15.1 && b > 1.9 && b < 2.1 &&
      c > 0.4 && c < 0.6 && d > 99.0 && d < 101.0)
    return 42;
  return 0;
}
