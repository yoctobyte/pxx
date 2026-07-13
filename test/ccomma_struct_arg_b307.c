/* A struct-valued comma expression passed BY VALUE.

   `f((a, b))` yields b. When b is a struct, the record-by-value path has to take b's
   ADDRESS to copy it into the argument temp -- but a comma is not an lvalue, so the
   whole thing fell through to a scalar lowering and the callee got a garbage pointer.
   Segfault. The same struct passed directly was fine, which is why no corpus caught it.

   IRLowerCallArg now unwraps the comma first: evaluate the left side for its effects,
   then lower the right side AS the argument, with the full parameter-aware treatment.
   That also covers arrays and strings behind a comma, not just records.

   Found by the csmith differential fuzzer (seed 5, reduced from 319 lines to this). */
int printf(const char *, ...);

struct S0 { short f0; unsigned short f1; };
struct Big { long a, b, c, d; };          /* > 8 bytes: forces the temp-copy path */

static int g_4 = 4;
static int *volatile g_3 = &g_4;
static struct S0 g_15 = {2, 7};
static struct Big g_big = {1, 2, 3, 4};
static int side = 0;

static unsigned f(struct S0 s, int a) { return (unsigned)s.f0 + s.f1 + a; }
static long fbig(struct Big b) { return b.a + b.b + b.c + b.d; }
static int bump(void) { side++; return 0; }

int main(void)
{
    printf("plain=%u\n", f(g_15, 1));
    printf("comma=%u\n", f(((*g_3), g_15), 1));
    printf("comma-big=%ld\n", fbig((bump(), g_big)));
    printf("nested-comma=%u\n", f((bump(), (*g_3), g_15), 1));
    printf("side=%d\n", side);          /* the left operands MUST still be evaluated */
    return 0;
}
