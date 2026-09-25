/* An object-like macro whose expansion ends in a function-like macro name
 * takes the '(...)' that follows it in the source (C99 6.10.3.4), at any depth.
 *
 * Only a one-level alias worked: `#define B F` then `B(x)` was redirected by a
 * special case that required the body to be EXACTLY a function-macro name. A
 * second alias, `#define A B`, reached the parser as `F (x)` and failed with
 * "call to undeclared function: F". stb_ds.h is built this way (shlen ->
 * stbds_shlen -> stbds_hmlen(t)). The object-macro arm now does the same
 * rescan the function-macro arm already did, so the special case is gone.
 *
 * Rows, each checked against gcc: 1 to 3 alias levels; an alias chain that
 * ends in a function macro whose argument is itself an alias; a body that
 * supplies its own '(' (H); a body with text before the name (P); nested use
 * (SA(SA(2))); recursion through an alias (Q/R must stop, not loop); a
 * self-alias of a real function (A2); a function-macro alias passed as a
 * value with no '(' (plus5x); a space and a newline before the '('. */
#include <stdio.h>

static int A2(int t) { return t + 1000; }
#define F(t) ((t) + 1)
#define B F
#define A B
#define Z A
#define X 20
#define Y X
#define H A(3)
#define P 100 + B
#define R(t) Q(t)
#define Q R
#define S(t) (t * 10)
#define SA S
#define A2 A2
static int apply(int (*f)(int), int v) { return f(v); }
static int plus5(int v) { return v + 5; }
#define plus5x plus5
int Q(int t) { return t - 1; }

int main(void)
{
    int x = 41;
    printf("%d %d %d %d\n", F(x), B(x), A(x), Z(x));
    printf("%d %d %d\n", A(Y), F(A(Y)), F(A(x)));
    printf("%d %d %d %d\n", H, P(1), SA(SA(2)), R(8));
    printf("%d %d %d %d\n", A2(1), apply(plus5x, 1), A (x), A
        (x));
    return 0;
}
