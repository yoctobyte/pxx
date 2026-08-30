/* C 6.3.1.8: two `float` operands give a `float`, and the arithmetic is done at
 * FLOAT width. We evaluated in double and rounded once at the end, which is a
 * different answer whenever the two roundings differ.
 *
 * Row 01 is the whole bug in one line: 0.300000004 (the double sum, widened)
 * against gcc's 0.300000012 (the single sum). Both read as "0.3" to a careless
 * eye, which is why it survived -- a wrong value that LOOKS RIGHT.
 *
 * Row 11 is why it is not a display question. `(a+b) == 0.3f` was FALSE where C
 * says true, so a program branches the other way. Row 12 is its companion, and
 * the pair is deliberate: a fix that made every float comparison true would pass
 * 11 and fail 12.
 *
 * Rows 06 and 15 are the controls that a fix applied one level too widely would
 * break -- `float + double` is a DOUBLE and must keep double precision, and a
 * double-only expression must not be narrowed at all. Row 17 asserts the static
 * type was already right, which is what says this was an EVALUATION-WIDTH bug
 * and not a typing one.
 *
 * Row 14 is the other direction: `(float)(0.1+0.2)` must narrow the double sum,
 * not compute at single width -- the cast and the operator round at different
 * points and must not be conflated.
 *
 * Oracle: gcc -O0, all 17 rows. Also measured on i386, aarch64, arm32 and
 * riscv32 under qemu: byte-identical to gcc on every row.
 * bug-c-float-plus-float-is-computed-at-double-width */
#include <stdio.h>

float g(float x, float y) { return x * y + x; }

int main(void)
{
  float a = 0.1f, b = 0.2f, c = 1.0f, d = 3.0f;
  double e = 0.1;
  int i = 7;

  printf("01 %.9f\n", (double)(a + b));
  printf("02 %.9f\n", (double)(a * b));
  printf("03 %.9f\n", (double)(c / d));
  printf("04 %.9f\n", (double)(a - b));
  printf("05 %.9f\n", (double)(a + b + a));   /* the roundings compose */
  printf("06 %.9f\n", (double)(a + e));       /* CONTROL: float+double is double */
  printf("07 %.9f\n", (double)(a + i));       /* float+int is float */
  { float t = a; t += b; printf("08 %.9f\n", (double)t); }
  { float t = c; t /= d; printf("09 %.9f\n", (double)t); }
  printf("10 %.9f\n", (double)g(c, d));       /* through a float-returning call */
  printf("11 %d\n", (a + b) == 0.3f);         /* the BRANCH, not the digits */
  printf("12 %d\n", (a + b) < 0.3f);          /* ...and it must not be true */
  { float s = 0.0f; int k;
    for (k = 0; k < 10; k++) s += 0.1f;
    printf("13 %.9f\n", (double)s); }         /* accumulated over a loop */
  printf("14 %.9f\n", (double)(float)(0.1 + 0.2));  /* cast narrows AFTER */
  printf("15 %.17g\n", 0.1 + 0.2);            /* CONTROL: double untouched */
  printf("16 %.9f\n", (double)(-a));
  printf("17 %d\n", (int)sizeof(a + b));      /* the static type was already 4 */
  return 0;
}
