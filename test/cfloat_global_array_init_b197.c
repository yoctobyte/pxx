/* Regression (bug-c-stb-sprintf-float-empty): a file-scope FLOAT/DOUBLE array
 * initializer was skipped (the flat-init path was ordinal-only), so the array
 * read back as all-zero — stb_sprintf's powten double tables were zero and every
 * %f/%g produced empty output. Now flat float array inits emit per-element float
 * PendingInits. Covers double + float, `[k]=` designators, and integer elements
 * assigned into a double array. Returns 42. */
#include <stdio.h>
static double  dt[4]  = {1.5, 2.5, 3.5, 4.5};
static float   ft[3]  = {10.0f, 20.0f, 30.0f};
static const double ct[3] = {0.25, 0.5, 0.75};
static double  desig[5] = {1.0, [3] = 8.0, 9.0};   /* [1],[2] stay 0 */
static double  ints[3] = {7, 8, 9};                /* int elements -> double */
int main(void) {
  double s = dt[0] + dt[3] + ft[2] / 10.0 + ct[1] + desig[3] + ints[0];
  /* 1.5 + 4.5 + 3.0 + 0.5 + 8.0 + 7.0 = 24.5 */
  if (desig[1] != 0.0 || desig[2] != 0.0) return 1;
  if (s < 24.0 || s > 25.0) { printf("s=%f\n", s); return 2; }
  return (int)(s + 17.5);   /* 24.5 + 17.5 = 42 */
}
