/* A struct returned by a function in ANOTHER freestanding object, called
   directly (l32r + callx) and through a function pointer, at 8 and 24 bytes.
   The caller must pass the hidden result pointer to an extern callee too
   (XtensaCallHasHiddenDest); Gibux's mount_ns_root stored through 0.
   The callees are in c_xtensa_extern_structret_b.c. Run under qemu-xtensa by
   tools/check_xtensa_freestanding_struct.py; check() & 255 == the gcc value.
   bug-esp-a-struct-returning-extern-call-passes-no-result-pointer */
struct path { void *a, *b; };
struct big { int w[6]; };
struct path g(void);
struct big mkbig(int k);
extern int one, two;
static int flag = 1;
static struct path f(void)
{
    if (flag)
        return g();
    struct path q = { 0, 0 };
    return q;
}
int check(void)
{
    struct path p = f();
    struct big (*fp)(int) = mkbig;
    struct big b = mkbig(3), c = fp(5);
    struct path (*gp)(void) = g;
    struct path r = gp();
    int s = 0, i;
    s += (p.a == &one) + 2 * (p.b == &two) + 4 * (r.a == &one) + 8 * (r.b == &two);
    for (i = 0; i < 6; i++) s += b.w[i] + 2 * c.w[i];
    return s;
}
