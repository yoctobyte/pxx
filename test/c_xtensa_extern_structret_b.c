/* The callees for c_xtensa_extern_structret_a.c, in their own object. */
struct path { void *a, *b; };
struct big { int w[6]; };
int one = 1, two = 2;
struct path g(void)
{
    struct path p = { &one, &two };
    return p;
}
struct big mkbig(int k)
{
    struct big b;
    int i;
    for (i = 0; i < 6; i++) b.w[i] = k * (i + 1);
    return b;
}
