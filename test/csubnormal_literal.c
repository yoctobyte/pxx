/* Subnormal double literals parse to their IEEE bits instead of 0
   (bug-c-float-literal-subnormal-parses-zero). DBL_TRUE_MIN, a mid-range
   subnormal, and the min-normal boundary — bit patterns = gcc's. */
int main(void) {
    typedef unsigned long long u64;
    double t = 4.9406564584124654e-324;   /* DBL_TRUE_MIN  -> 0x1 */
    double s = 1.2345678e-310;            /* 0x16b9f4b7f7d1 */
    double n = 2.2250738585072014e-308;   /* min normal    -> 0x10000000000000 */
    int ok = 0;
    if (*(u64*)&t == 1ull) ok++;
    if (*(u64*)&s == 0x16b9f4b7f7d1ull) ok++;
    if (*(u64*)&n == 0x10000000000000ull) ok++;
    return ok == 3 ? 42 : ok;
}
