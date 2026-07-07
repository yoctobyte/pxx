/* b186: C block scope — an inner declaration SHADOWS the outer one and DIES
   at the closing brace (tcc's struct_decl shadows `v` in a nested block; the
   flat-scope model clobbered the outer v and corrupted symbol tokens). */
typedef struct S { int v; } S;
int use(int x) { return x; }
int main(void)
{
    int v = 5;
    S s; S *ref = &s;
    int sum = 0;
    s.v = 77;
    if (v == 5) {
        int v = ref->v;          /* shadows; reads the FIELD v */
        if (v != 77) return 1;
        {
            int v = 9;           /* two levels deep */
            sum += v;            /* 9 */
        }
        sum += v;                /* 77 */
    }
    sum += v;                    /* 5 — outer v untouched */
    if (sum != 91) return 2;
    {
        int q = 3;
        sum += use(q);
    }
    /* q is dead here; a new q in a sibling block is a fresh variable */
    {
        int q = 4;
        sum += use(q);
    }
    if (sum != 98) return 3;
    if (v != 5) return 4;
    return 42;
}
