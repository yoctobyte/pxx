/* A float converted to unsigned long long, for values from 2^63 up.
   pxx used the SIGNED conversion, so every one of these came back
   9223372036854775807 (High(Int64)) on every target; found by tcc's
   tests2/134 under a pxx-built tcc. Each shape the conversion is reached by:
   cast, init, assignment, struct field, array element, global, a u64
   parameter, compound assignment, and a float (not double) source.
   The expected values are gcc's; none of them equals the saturation value. */
#include <stdio.h>
struct S { unsigned long long u; int k; };
static unsigned long long take(unsigned long long u) { return u; }
static unsigned long long gu;
int main(void) {
  volatile double v[6] = { 1e19, 9223372036854775808.0, 1.8e19,
                           18446744073709549568.0, 9223372036854774784.0, 3.7 };
  volatile float f = 1e19f;
  struct S s; unsigned long long arr[2], x; int i;
  for (i = 0; i < 6; i++) {
    double d = v[i];
    unsigned long long a = d;
    unsigned long long y = 5;
    x = 0; x = d;
    s.u = d;
    arr[1] = d;
    gu = d;
    y += d;
    printf("%d %llu %llu %llu %llu %llu %llu %llu %llu\n", i,
           (unsigned long long)d, a, x, s.u, arr[1], gu, take(d), y);
  }
  printf("float %llu\n", (unsigned long long)f);
  return 0;
}
