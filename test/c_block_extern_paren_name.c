/* A parenthesised name in a block-scope extern is a grouping: NetBSD's
   __link_set_decl inside a function. Both bounds read 0 and the loop never ran
   (rump prop_kern_init initialised no pool).
   bug-c-a-parenthesised-block-scope-extern-name-is-not-declared */
struct pi { int v; };
int sum(void)
{
    extern struct pi * const (__start_link_set_t)[] __attribute__((__visibility__("hidden")));
    __asm__(".hidden " "__stop_link_set_t");
    extern struct pi * const (__stop_link_set_t)[] __attribute__((__weak__)) __attribute__((__visibility__("hidden")));
    extern int (plain_v);
    struct pi * const *p;
    int s = plain_v;
    for (p = (__start_link_set_t); p < (__stop_link_set_t); p++)
        s += (*p)->v;
    return s;
}
