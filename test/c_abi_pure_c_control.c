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
double cee_mix4(int i1, double d1, int i2, double d2)
{ return (double)i1*1000.0 + d1*100.0 + (double)i2*10.0 + d2; }
int cee_eight(int a, int b, int c, int d, int e, int f, int g, int h)
{ return a*1 + b*2 + c*3 + d*4 + e*5 + f*6 + g*7 + h*8; }

/* A STRUCT RETURNED BY VALUE ACROSS A C-ABI CALL. The inner call is the shape
   under test; the wrapper returns a plain double so all three subjects in this
   family can share one expected line.

   This is crtl's own `sin`: its kernels return a two-double `crtl_dd` by value,
   and the cdecl call arms on i386, arm32 and aarch64 never set the hidden
   destination register the callee prologue reads (ecx / r12 / x8) -- so
   `sin(2)` SEGFAULTED on three targets the moment a C function always used the
   C ABI, while `sqrt(4.0)` was fine. Nothing that returns a struct had ever
   come down that path before, so the arm had no code and no test.
   bug-c-a-c-function-s-calling-convention-depends-on-the-target */
struct cee_pair { double hi; double lo; };
static struct cee_pair cee_mkpair(double a, double b)
{ struct cee_pair p; p.hi = a; p.lo = b; return p; }
double cee_pairsum(double a, double b)
{ struct cee_pair p = cee_mkpair(a * 10.0, b); return p.hi + p.lo; }


int main(void)
{
  printf("dbl_first %.2f\n",  cee_dbl_first(2.5, 4));
  printf("int_first %.2f\n",  cee_int_first(4, 2.5));
  printf("three_ints %d\n",   cee_three_ints(1, 2, 3));
  printf("two_dbl %.2f\n",    cee_two_dbl(1.5, 2.5));
  printf("flt %.2f\n",        (double)cee_flt(2.5, 4));
  printf("mix4 %.2f\n",       cee_mix4(1, 2.0, 3, 4.0));
  printf("eight %d\n",        cee_eight(1, 2, 3, 4, 5, 6, 7, 8));
  printf("pairsum %.2f\n",    cee_pairsum(1.5, 2.5));
  return 0;
}
