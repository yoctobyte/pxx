/* cdecl INDIRECT calls past the AAPCS64 register banks -- the third of the three
   C-ABI call kinds, and the last one that refused.

   aarch64 had four separate "more than 8 arguments" refusals. The direct and
   variadic arms lost theirs in fc9c8ade2; this file is the one that was left,
   `cdecl indirect call with more than 8 arguments not supported`, which fired
   for any call through a function POINTER with a ninth argument.

   Three shapes, because one bank overflowing does not exercise the other:
     ten      10 ints   -- GP bank overflows, FP bank untouched
     mixed12  6+6       -- both banks overflow, and NSAA interleaves them
     tendbl   10 doubles-- FP bank overflows, GP bank untouched
   Weighted 1..12 so any permutation of the stack arguments changes the answer;
   a truncated or mis-advanced NSAA cannot produce the right total by accident.

   Values are gcc's, not ours: 385 / 650.00 / 385.00 from `gcc -O0` natively.
   bug-a-aarch64-has-no-stack-argument-passing-for-the-three-c-abi-call-kinds */
#include <stdio.h>
static int  ten(int a,int b,int c,int d,int e,int f,int g,int h,int i,int j)
{ return a*1+b*2+c*3+d*4+e*5+f*6+g*7+h*8+i*9+j*10; }
static double mixed12(int a,double b,int c,double d,int e,double f,
                      int g,double h,int i,double j,int k,double l)
{ return a*1+b*2+c*3+d*4+e*5+f*6+g*7+h*8+i*9+j*10+k*11+l*12; }
static double tendbl(double a,double b,double c,double d,double e,
                     double f,double g,double h,double i,double j)
{ return a*1+b*2+c*3+d*4+e*5+f*6+g*7+h*8+i*9+j*10; }
int main(void){
  int (*p1)(int,int,int,int,int,int,int,int,int,int) = ten;
  double (*p2)(int,double,int,double,int,double,int,double,int,double,int,double) = mixed12;
  double (*p3)(double,double,double,double,double,double,double,double,double,double) = tendbl;
  printf("ten %d\n", p1(1,2,3,4,5,6,7,8,9,10));
  printf("mixed12 %.2f\n", p2(1,2,3,4,5,6,7,8,9,10,11,12));
  printf("tendbl %.2f\n", p3(1,2,3,4,5,6,7,8,9,10));
  return 0;
}
