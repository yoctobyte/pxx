/* Branch-context compares, x +- small constants and ++/-- whose value is
   unused, against gcc. Exercises the paths of
   feature-xtensa-codegen-density-before-register-allocation: a comparison
   deciding a branch is one bxx (signed, unsigned, `c == 0` / `c != 0` of a
   comparison folded); a leaf right operand loads straight into a register;
   x + k / x - k with k near addi's limits; `v++` as a statement, a for step
   and a comma operand on every scalar kind (char and short wrap at their
   width, a pointer steps by its element). */
#ifdef DENSITY_BARE
/* windowed xtensa has no hosted C entry: tools/check_xtensa_density.py links
   this as an --emit-obj with test/c_xtensa_windowed_start.S, which exits with
   check(). Every printed value is also mixed into h, so h & 255 covers them. */
#define printf(...) 0
#else
#include <stdio.h>
#endif

static unsigned h = 2166136261u;
static void mix(long v) { h = (h ^ (unsigned)v) * 16777619u; }

int g_i = 7;
unsigned char g_uc = 254;
signed char g_sc = 126;
short g_s = 32766;
unsigned short g_us = 65534;
long long g_ll = 0x7fffffffLL;
int g_arr[6] = { 10, 20, 30, 40, 50, 60 };

static int vals[] = { -2147483647 - 1, -129, -128, -127, -2, -1, 0, 1, 2, 7, 8, 9, 10, 127, 128, 255, 256, 257, 300, 32767, 32768, 65535, 65536, 2147483647 };

static int cmp_signed(int a, int b)
{
    int r = 0;
    if (a < b) r |= 1;
    if (a <= b) r |= 2;
    if (a > b) r |= 4;
    if (a >= b) r |= 8;
    if (a == b) r |= 16;
    if (a != b) r |= 32;
    if (!(a < b)) r |= 64;
    if ((a < b) == 0) r |= 128;
    if ((a > b) != 0) r |= 256;
    if (a) r |= 512;
    if (!a) r |= 1024;
    while (a > b) { r |= 2048; break; }
    return r;
}

static int cmp_unsigned(unsigned a, unsigned b)
{
    int r = 0;
    if (a < b) r |= 1;
    if (a <= b) r |= 2;
    if (a > b) r |= 4;
    if (a >= b) r |= 8;
    if (a == b) r |= 16;
    if (a != b) r |= 32;
    if ((a >= b) == 0) r |= 64;
    if (a < 3u) r |= 128;
    if (a > 200u) r |= 256;
    if (a < 32768u) r |= 512;
    if (a >= 65536u) r |= 1024;
    if (a <= 32767u) r |= 2048;
    if (a > 65535u) r |= 4096;
    if (a < 2u) r |= 8192;
    if (a >= 256u) r |= 16384;
    if (a <= 0xFFFFFFFFu) r |= 32768;
    return r;
}

static int cmp_const(int a)
{
    int r = 0;
    if (a < 0) r |= 1;
    if (a >= 0) r |= 2;
    if (a == 127) r |= 4;
    if (a > -128) r |= 8;
    if (a <= 128) r |= 16;
    if (a != 100000) r |= 32;
    if (a < -100000) r |= 64;
    /* the b4const immediates and their neighbours (a > k is a >= k+1) */
    if (a == 1) r |= 128;
    if (a != -1) r |= 256;
    if (a < 8) r |= 512;
    if (a >= 10) r |= 1024;
    if (a > 255) r |= 2048;
    if (a <= 127) r |= 4096;
    if (a > -2) r |= 8192;
    if (a <= 9) r |= 16384;
    if (a == 256) r |= 32768;
    if (a > 300) r |= 65536;
    return r;
}

static int cmp_char(unsigned char c, signed char s)
{
    int r = 0;
    if (c > 127) r |= 1;
    if (s < 0) r |= 2;
    if (c == (unsigned char)s) r |= 4;
    if (s > c) r |= 8;
    return r;
}

static long addk(int x)
{
    long s = 0;
    s += x + 127; s += x - 127; s += x + 128; s += x - 128;
    s += x + -127; s += x - -127; s += x + 1; s += x - 1;
    s += x + 2047; s += x - 2048; s += x + 100000;
    return s;
}

/* commutative ops with a leaf left and a computed, effect-free right: the
   right is evaluated first and the leaf read after (xtensa XtNoEffects) */
static long commute(int a, int b, const int *p)
{
    long s = 0;
    int t = 3;
    s += a + b * 7;
    s += t * (a - b);
    s += g_i & (p[1] | 6);
    s += t | (p[0] ^ a);
    s += g_i ^ (*p + b * a);
    s += a + (b + (a * t));
    s += (long)(unsigned)(t * (p[2] >> 1)) + a;
    return s;
}

int main(void)
{
    int i, j, n;
    for (i = 0; i < (int)(sizeof vals / sizeof vals[0]); i++)
        for (j = 0; j < (int)(sizeof vals / sizeof vals[0]); j++) {
            mix(cmp_signed(vals[i], vals[j]));
            mix(cmp_unsigned((unsigned)vals[i], (unsigned)vals[j]));
        }
    for (i = 0; i < (int)(sizeof vals / sizeof vals[0]); i++) {
        mix(cmp_const(vals[i]));
        mix(cmp_char((unsigned char)vals[i], (signed char)vals[i]));
        mix(addk(vals[i]));
        mix(commute(vals[i], vals[(i + 3) % (int)(sizeof vals / sizeof vals[0])], g_arr + (i % 3)));
    }
    printf("cmp %08x\n", h);

    /* ++/-- as statements, on every scalar kind, locals and globals */
    {
        signed char c = 126; unsigned char uc = 255; signed char sc = -128;
        short s = -32768; unsigned short us = 0; int x = 2147483646;
        unsigned u = 0; long long ll = -1; unsigned long long ull = 0xffffffffULL;
        int *p = g_arr; char *cp = (char *)g_arr;
        c++; c++; uc++; sc--; s--; us--; x++; u--; ll++; ull++; p++; p++; cp++;
        ++c; --uc; ++sc; ++s; ++us; --x; ++u; --ll; --ull; --p; ++cp;
        g_i++; g_uc++; g_uc++; g_sc++; g_sc++; g_s++; g_s++; g_us++; g_us++; g_ll++;
        --g_i;
        mix(c); mix(uc); mix(sc); mix(s); mix(us); mix(x); mix(u); mix((long)ll); mix((long)ull);
        mix(*p); mix((long)(cp - (char *)g_arr));
        mix(g_i); mix(g_uc); mix(g_sc); mix(g_s); mix(g_us); mix((long)g_ll); mix((long)(g_ll >> 32));
        printf("loc %d %u %d %d %u %d %u %lld %llu %d %d\n", c, uc, sc, s, us, x, u, ll, ull,
               *p, (int)(cp - (char *)g_arr));
        printf("glb %d %u %d %d %u %lld\n", g_i, g_uc, g_sc, g_s, g_us, g_ll);
    }

    /* for steps and comma operands; the value of a postfix still used */
    {
        int sum = 0, k = 0, m = 10, q;
        unsigned char b;
        for (i = 0, j = 10; i < j; i++, j--) sum += i * j;
        for (b = 250; b != 4; b++) sum += b;
        for (n = 5; n; n--) sum += n;
        q = k++; sum += q * 100 + k;
        q = ++k; sum += q * 1000;
        q = (m--, m--, m); sum += q;
        mix(sum); mix(k); mix(m);
        printf("loop %d %d %d\n", sum, k, m);
    }
    printf("all %08x\n", h);
    return 0;
}

#ifdef DENSITY_BARE
int check(void)
{
    main();
    return (int)(h & 255);
}
#endif
