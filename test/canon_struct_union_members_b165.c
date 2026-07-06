/* Regression: C11 anonymous struct/union members — an unnamed aggregate's fields
   are promoted into the enclosing struct at the member's offset, incl. nesting.
   Returns 42. */
typedef struct {
    int a;
    union { int b1; int b2; };            /* anon union: v.b1 / v.b2 */
    struct { union { struct { int c; }; }; };  /* deeply nested anon: v.c */
    struct { int d; };                    /* anon struct: v.d */
} S;
int main(void) {
    S v;
    v.a = 1; v.b1 = 2; v.c = 3; v.d = 4;
    if (v.a != 1) return 1;
    if (v.b1 != 2 || v.b2 != 2) return 2;   /* union alias */
    if (v.c != 3) return 3;
    if (v.d != 4) return 4;
    return 42;
}
