#include <stdio.h>
#include <math.h>
int main(void) {
  printf("pow=%g %g\n", pow(2.0,10.0), pow(2.0,0.5));
  printf("log=%.9f log10=%.9f log2=%.9f\n", log(4.0), log10(1000.0), log2(8.0));
  printf("exp=%.9f\n", exp(1.0));
  /* ASYMMETRIC arguments. atan2(1,1) is pi/4, which is also atan(1), so a
     hijacked or argument-swapped atan2 answers correctly and the check passes:
     that exact blind spot let a Pascal Atan2 ship broken for one commit
     (cmath_trig_family_b385 went red). atan2(0.5,1) != atan2(1,0.5). */
  printf("atan2=%.9f %.9f %.9f\n", atan2(1.0,1.0), atan2(0.5,1.0), atan2(1.0,0.5));
  printf("copysign=%g %g\n", copysign(3.0,-1.0), copysign(-3.0,1.0));
  printf("isnan=%d %d\n", isnan(0.0/0.0), isnan(1.0));
  printf("isinf=%d %d\n", isinf(1.0/0.0), isinf(1.0));
  printf("nan=%d %d\n", isnan(nan("")), isnan(nan("0")));
  printf("hypot=%.9f fmod=%g\n", hypot(3.0,4.0), fmod(7.0,3.0));
  printf("sqrt=%.9f ceil=%g floor=%g\n", sqrt(2.0), ceil(-2.5), floor(-2.5));
  return 0;
}
