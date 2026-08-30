/* The regression half of test/test_c_abi_pascal_caller.pas: the SAME functions
   and the SAME expected values, called from C instead of from Pascal.

   It is the control that makes a convention change honest. Fixing the
   Pascal-caller path by giving a C function the C ABI is only correct if this
   file does not move -- and MEASURED 2026-08-30, paired on identical source,
   routing the C prologue through EmitParamSpillsForTarget plus deleting the
   seven `not CProgramMode` guards takes the Pascal-caller test from 3 failures
   to 1 on aarch64, from red to GREEN on arm32, and fixes i386's argument order,
   while taking THIS file from clean to a flt failure on aarch64 and to a
   COMPILE FAILURE on arm32 and i386. The shared arm cannot yet do the job it
   would be given -- see
   bug-a-the-shared-cdecl-spill-arm-cannot-yet-do-the-job-it-would-be-given.

   GREEN ON ALL FIVE, and it took a fix to make that true. The first cut of this
   file asserted it on x86-64 evidence alone and was wrong on three targets:
   `flt` was 0.00 on arm32 and riscv32 and garbage on i386, because
   `printf("%.2f", (double)f)` handed a variadic argument four single bytes
   where eight were expected. That was a real, separate defect
   (bug-c-a-float-to-double-cast-is-a-retag-not-a-conversion), now fixed, so the
   cross rows are asserted rather than skipped -- which is the whole point of a
   control: an unmeasured baseline in one does not merely weaken the comparison,
   it inverts the sign of every finding drawn from it.
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
