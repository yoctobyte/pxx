int printf(const char *fmt, ...);
static long f8(long a, long b, long c, long d, long e, long f, long g, long h) {
    return a*10000000 + b*1000000 + c*100000 + d*10000 + e*1000 + f*100 + g*10 + h;
}
static double fm(long a, double x, long b, long c, long d, long e, long f, long g, double y, long h) {
    return a + b + c + d + e + f + g + h + x * y;
}
typedef long (*fp8)(long, long, long, long, long, long, long, long);
typedef double (*fpm)(long, double, long, long, long, long, long, long, double, long);
int main(void) {
    fp8 p = f8;
    fpm q = fm;
    long r = p(1, 2, 3, 4, 5, 6, 7, 8);
    double s = q(1, 2.5, 2, 3, 4, 5, 6, 7, 4.0, 8);   /* 36 + 10.0 = 46 */
    printf("%ld %.1f\n", r, s);
    if (r == 12345678 && s == 46.0) return 42;
    return 1;
}
