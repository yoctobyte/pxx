/* The regression half of test/test_c_abi_pascal_caller.pas: the SAME functions
   and the SAME expected values, called from C instead of from Pascal.

   It is the control that makes a convention change honest. Fixing the
   Pascal-caller path by giving a C function the C ABI is only correct if this
   file does not move -- and MEASURED 2026-08-30, paired on identical source
   (8a42f93ffe74 -> 7d91463cbbfc), routing the C prologue through
   EmitParamSpillsForTarget plus deleting the seven `not CProgramMode` guards
   takes the Pascal-caller test from 3 failures to 1 on aarch64, from red to
   GREEN on arm32, and fixes i386's argument order -- while taking THIS file
   from clean to a flt failure on aarch64 and from a value failure to a COMPILE
   FAILURE on arm32 and i386. The shared arm cannot yet do the job it would be
   given; see the prerequisite ticket named below.

   WIRED ON x86-64 ONLY, and that is not laziness -- `flt` is ALREADY broken on
   three cross targets before any of this work, so the cross rows cannot be
   asserted as green:

     x86-64   clean
     aarch64  clean
     arm32    flt 0.00
     riscv32  flt 0.00
     i386     flt -7.55e307

   riscv32 is the tell that this is a SEPARATE, pre-existing defect rather than
   anything to do with the calling convention: nothing about riscv32 changes in
   that work, and it fails `flt` today. A `float` parameter and `float` return
   in a plain C program are wrong on three targets right now.
   bug-c-a-float-parameter-and-return-are-wrong-in-pure-c-on-three-targets

   I asserted "green on all five today" in the first cut of this file having
   verified only x86-64. It was false on three targets. Recorded rather than
   quietly corrected, because an unmeasured baseline in a CONTROL is the one
   place it does the most damage.
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
