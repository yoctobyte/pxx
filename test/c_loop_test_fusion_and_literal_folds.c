/* A C `for` with a step is `if (cond == 0) break`, and its condition arrives
   as the compare in a truth wrapper. The IR now branches on the compare
   itself, inverting it for `== 0` on ordinal and pointer operands (never on
   a float: NaN), and folds literal arithmetic such as the `4 * 8` of a
   pointer step. Every row is checked against gcc. Rainyday 0060. */
#include <stdio.h>
#include <stdint.h>

static int count_u(unsigned lo, unsigned hi)
{
    int n = 0;
    for (unsigned u = lo; u <= hi; u++) {
        n++;
        if (u == 0xFFFFFFFFu) break;
    }
    return n;
}

static int count_s(int lo, int hi, int step)
{
    int n = 0;
    for (int i = lo; i < hi; i += step) n++;
    for (int i = hi; i > lo; i -= step) n++;
    for (int i = lo; i != hi; i++) n++;
    for (int i = lo; i >= lo && i <= hi; i++) n++;
    return n;
}

static long walk(const uint64_t *p, const uint64_t *end)
{
    long s = 0;
    for (; p < end; p += 2) s += (long)*p;
    for (p -= 2; p >= end - 6; p -= 3) s ^= (long)*p;
    return s;
}

static int nan_loop(double x)
{
    int n = 0;
    for (double d = x; d < 3.0; d += 1.0) { n++; if (n > 5) break; }
    for (double d = x; !(d >= 3.0); d += 1.0) { n += 10; if (n > 100) break; }
    return n;
}

static int chars(const char *s)
{
    int n = 0;
    for (; *s != '\0'; s++)
        for (char c = 'a'; c <= *s; c++) n++;
    return n;
}

int main(void)
{
    uint64_t v[12];
    for (int i = 0; i < 12; i++) v[i] = (uint64_t)(i * i + 3);
    printf("%d %d %d\n", count_u(0, 5), count_u(0xFFFFFFF0u, 0xFFFFFFFFu), count_u(7, 3));
    printf("%d %d %d\n", count_s(0, 10, 3), count_s(-5, 5, 2), count_s(-2147483647 - 1, -2147483647 + 5, 1));
    printf("%ld\n", walk(v, v + 12));
    double z = 0.0;
    printf("%d %d %d\n", nan_loop(0.5), nan_loop(z / z), nan_loop(5.0));
    printf("%d\n", chars("abcxyz"));
    int a = 3 * 7 + 2 - 4;
    long b = 1000000 * 2000;
    unsigned c = 4000000000u + 1;
    int8_t d = (int8_t)(100 + 100);
    uint8_t e = (uint8_t)(200 + 100);
    printf("%d %ld %u %d %d\n", a, b, c, d, e);
    return 0;
}
