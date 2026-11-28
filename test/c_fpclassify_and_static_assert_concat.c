/* SPDX-License-Identifier: Zlib */
/* fpclassify/isnormal on float and double edge values, and a _Static_assert
   whose message is adjacent string literals (libinput). Row c_fpcls26,
   against gcc. feature-crtl-fpclassify-and-isnormal,
   bug-c-static-assert-message-of-adjacent-string-literals */
#include <stdio.h>
#include <math.h>
#include <float.h>
#include <assert.h>

enum level { LOW, HIGH };
#define ASSERT_INT_SIZE(type_) \
	static_assert(sizeof(type_) == sizeof(unsigned int), \
		      "sizeof("  #type_ ") must be sizeof(uint)")
ASSERT_INT_SIZE(enum level);
_Static_assert(1, "a(" "b" ")");

int main(void)
{
    double d[] = { 0.0, -0.0, 1.0, -2.5, DBL_MIN, DBL_MIN / 4, DBL_MAX,
                   HUGE_VAL, -HUGE_VAL, NAN };
    float f[] = { 0.0f, -0.0f, 1.0f, FLT_MIN, FLT_MIN / 4, FLT_MAX,
                  HUGE_VALF, NAN };
    unsigned i;
    for (i = 0; i < sizeof d / sizeof d[0]; i++)
        printf("d%u %d %d\n", i, fpclassify(d[i]), isnormal(d[i]) != 0);
    for (i = 0; i < sizeof f / sizeof f[0]; i++)
        printf("f%u %d %d\n", i, fpclassify(f[i]), isnormal(f[i]) != 0);
    printf("names %d %d %d %d %d\n", FP_NAN, FP_INFINITE, FP_ZERO, FP_SUBNORMAL, FP_NORMAL);
    return 0;
}
