/* alloca and variable-length arrays in a --freestanding object (a kernel's
   code: no red zone, an interrupt arrives on the same stack). IR_ALLOCA
   parks its three registers in frame slots, not below rsp.
   tools/check_freestanding_vla_sse.py links this with gcc and runs check().
   feature-c-freestanding-vla-frame-slots-and-sse-refusal */
static long sum(const unsigned char *p, int n)
{
    long s = 0;
    for (int i = 0; i < n; i++) s += p[i];
    return s;
}

static int fill(unsigned char *b, int n, int seed)
{
    for (int i = 0; i < n; i++) b[i] = (unsigned char)(seed + i);
    return n;
}

long vla(int n)
{
    unsigned char a[n];
    fill(a, n, 1);
    unsigned char b[n * 2];
    fill(b, n * 2, 3);
    return sum(a, n) * 1000 + sum(b, n * 2);
}

/* an alloca in the middle of an expression whose left operand is live on
   the expression stack: the copy-down path */
long mid(int n)
{
    long k = 7;
    long r = k * 100 + fill(__builtin_alloca(n), n, 5) + k;
    return r;
}

long check(void)
{
    return vla(10) * 10000 + mid(33) + vla(1);
}
