/* The regression half of test/test_c_abi_pascal_caller.pas: the SAME functions
   and the SAME expected values, called from C instead of from Pascal.

   This one is green on all five targets TODAY and must stay green. It is the
   control that makes a convention change honest: fixing the Pascal-caller path
   by giving a C function the C ABI is only correct if the C-mode call sites
   move with it. Measured 2026-08-30 -- changing the prologue alone takes this
   file from clean on all five to wrong on aarch64, a compile failure on arm32
   and a segfault on i386, while the Pascal-caller test above goes green. Either
   both halves move or neither does.
   bug-c-a-c-function-s-calling-convention-depends-on-the-target */

#include <stdio.h>

double cee_dbl_first(double x, int n)      { return x * (double)n; }
double cee_int_first(int n, double x)      { return x * (double)n; }
int    cee_three_ints(int a, int b, int c) { return a*100 + b*10 + c; }
double cee_two_dbl(double a, double b)     { return a*10.0 + b; }
float  cee_flt(float f, int n)             { return f * (float)n; }

int main(void)
{
  printf("dbl_first %.2f\n",  cee_dbl_first(2.5, 4));
  printf("int_first %.2f\n",  cee_int_first(4, 2.5));
  printf("three_ints %d\n",   cee_three_ints(1, 2, 3));
  printf("two_dbl %.2f\n",    cee_two_dbl(1.5, 2.5));
  printf("flt %.2f\n",        (double)cee_flt(2.5, 4));
  return 0;
}
