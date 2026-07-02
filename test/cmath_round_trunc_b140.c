/* SPDX-License-Identifier: MPL-2.0 */
/* math.h round()/trunc() compiled clean but died at load with `undefined
   symbol: round` — Pascal Round/Trunc are compiler intrinsics with no
   linkable symbol for the case-insensitive extern bind, unlike sqrt/floor/
   ceil (bug-c-math-round-undefined-symbol). Now pure-C impls in crtl math.c
   with C semantics: round = half away from zero (NOT Pascal nearest-even),
   trunc = toward zero. Exit 42 on success. */
#include <math.h>

int main(void) {
    int ok = 1;
    if ((int)(round(3.5))  !=  4) ok = 0;
    if ((int)(round(2.5))  !=  3) ok = 0;   /* half away from zero, not banker's 2 */
    if ((int)(round(-2.5)) != -3) ok = 0;
    if ((int)(round(-3.2)) != -3) ok = 0;
    if ((int)(round(3.49)) !=  3) ok = 0;
    if ((int)(trunc(3.9))  !=  3) ok = 0;
    if ((int)(trunc(-3.9)) != -3) ok = 0;
    if ((int)(trunc(0.0))  !=  0) ok = 0;
    /* neighbours from the same header keep binding to the Pascal RTL */
    if ((int)(floor(3.9))  !=  3) ok = 0;
    if ((int)(ceil(3.1))   !=  4) ok = 0;
    return ok ? 42 : 1;
}
