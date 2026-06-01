/* Helpers for the C argument stack-spill regression. Each returns the sum of
   all arguments so the result verifies every register and stack slot. */
long sum7(long a, long b, long c, long d, long e, long f, long g) {
    return a + b + c + d + e + f + g;
}
double dsum10(double a, double b, double c, double d, double e,
              double f, double g, double h, double i, double j) {
    return a + b + c + d + e + f + g + h + i + j;
}
long mix9(long a, double b, long c, long d, long e,
          long f, long g, long h, double i) {
    return a + (long)b + c + d + e + f + g + h + (long)i;
}
