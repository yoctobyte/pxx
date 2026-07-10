/* b233 (bug-c-duktape-double-formatting residual, Track B crtl/RTL): C math
   domain errors must be IEEE. crtl sqrt/log bind case-insensitively to Pascal
   Sqrt/Ln (lib/rtl/math.pas), which returned 0 for out-of-domain inputs:
   sqrt(-1) gave 0 (want NaN), and log would give 0 for both 0 and negatives
   (want -Inf and NaN). duktape's Math.sqrt(-1) printed 0 instead of NaN.
   Detect via bit pattern (compiler-independent, no reliance on NaN !=).
   Exit 42 = pass. */
static int is_nan(double d)  { unsigned long long b = *(unsigned long long*)&d;
                               return (((b>>52)&0x7ff)==0x7ff) && ((b & 0xFFFFFFFFFFFFFULL)!=0); }
static int is_ninf(double d) { unsigned long long b = *(unsigned long long*)&d;
                               return b == 0xFFF0000000000000ULL; }
extern double sqrt(double);
extern double log(double);
int main(void) {
    volatile double n1 = -1.0, z = 0.0, four = 4.0, e = 2.718281828459045;
    if (!is_nan(sqrt(n1)))   return 1;   /* sqrt(-1) = NaN */
    if (sqrt(z)   != 0.0)    return 2;   /* sqrt(0)  = 0   (0==0 ok even pre-fix) */
    if (sqrt(four) < 1.999 || sqrt(four) > 2.001) return 3;
    if (!is_nan(log(n1)))    return 4;   /* log(-1)  = NaN */
    if (!is_ninf(log(z)))    return 5;   /* log(0)   = -Inf */
    if (log(e) < 0.999 || log(e) > 1.001) return 6;
    return 42;
}
