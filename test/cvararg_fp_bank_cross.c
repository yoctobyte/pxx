/* AAPCS64 §6.4.2: a variadic FLOAT argument goes in the FP bank (v0..v7), not
   the GP one — so a pxx-compiled variadic CALLEE must save v0..v7 and select
   the FP area in va_arg. Every other C variadic test in this suite is
   native-only, and the defect this covers is invisible on x86-64: caller and
   callee were both all-GP on aarch64, self-consistently, so crtl's own printf
   read the float back from the same wrong place and printed the right answer.
   Only a FOREIGN callee saw it (test_pascal_varargs_external, via glibc), and
   fixing the caller alone silently inverted which side was wrong.

   The rows are chosen so no bank stays inside its easy case: a NAMED double
   ahead of the tail (va_start's fp_offset seed), the two banks advancing
   independently, more variadic doubles than the 8 FP registers hold, and more
   variadic ints than the 8 GP ones with a double behind them.
   bug-a-aarch64-passes-a-variadic-float-in-an-fp-register-so-glibc-reads-zero */
#include <stdio.h>
#include <stdarg.h>

static double scaled(double scale, int n, ...) {
  va_list ap; int i; double s = 0;
  va_start(ap, n);
  for (i = 0; i < n; i++) s += va_arg(ap, double);
  va_end(ap);
  return s * scale;
}

static void inter(int n, ...) {
  va_list ap; int i;
  va_start(ap, n);
  for (i = 0; i < n; i++) {
    int k = va_arg(ap, int);
    double d = va_arg(ap, double);
    printf(" %d:%.2f", k, d);
  }
  va_end(ap);
  printf("\n");
}

static double sumd(int n, ...) {
  va_list ap; int i; double s = 0;
  va_start(ap, n);
  for (i = 0; i < n; i++) s += va_arg(ap, double);
  va_end(ap);
  return s;
}

static void mixmany(int n, ...) {
  va_list ap; int i;
  va_start(ap, n);
  for (i = 0; i < n; i++) printf(" %d", va_arg(ap, int));
  printf(" | %.2f\n", va_arg(ap, double));
  va_end(ap);
}

int main(void) {
  printf("scaled=%.2f\n", scaled(2.0, 3, 1.0, 0.5, 1.5));
  printf("inter:"); inter(3, 1, 1.5, 2, 2.5, 3, 3.5);
  printf("sumd=%.2f\n", sumd(10, 1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.0,9.0,10.0));
  printf("mixmany:"); mixmany(9, 1,2,3,4,5,6,7,8,9, 2.25);
  printf("direct=%.2f %.2f %.2f %.2f %.2f %.2f %.2f %.2f %.2f\n",
         1.0,2.0,3.0,4.0,5.0,6.0,7.0,8.0,9.5);
  return 0;
}
