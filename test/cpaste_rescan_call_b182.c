/* b182: C99 6.10.3.4 rescan — a macro expansion whose output ends in a
   function-like macro name must consume the trailing (...) from the source
   and expand it. Covers 00201 (multi-level CAT chain) and tcc's ELFW pattern,
   plus negative guards (name-as-object, blue-paint self-ref). */

/* single-level: object alias -> function macro (A/B stay undefined for CAT) */
#define G(x) ((x)+1)
#define AL G

/* tcc ELFW pattern: paste emerges a function-macro name */
#define ELFW(t) ELF##64##_##t
#define ELF64_V(o) ((o)&3)

/* 00201 multi-level: the func-macro name only appears after nested rescan */
#define CAT2(a,b) a##b
#define CAT(a,b) CAT2(a,b)
#define AB(x) CAT(x,y)
#define xy 39

/* negative: blue-paint self-reference must not loop or over-consume */
int f(int x) { return x + 1; }
#define f(x) (f)(x)

int main(void)
{
    int r = 0;
    r += AL(4) == 5;       /* alias call */
    r += ELFW(V)(7) == 3;  /* paste -> call */
    r += CAT(A,B)(x) == 39;/* multi-level -> call */
    r += f(1) == 2;        /* blue-painted (f)(x) */
    if (r == 4)
        return 42;
    return r;
}
